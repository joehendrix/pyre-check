(*
 * Copyright (c) Meta Platforms, Inc. and affiliates.
 *
 * This source code is licensed under the MIT license found in the
 * LICENSE file in the root directory of this source tree.
 *)

(**
 * Hh_json parsing and pretty printing library.
*)

type json =
    JSON_Object of (string * json) list
  | JSON_Array of json list
  | JSON_String of string
  | JSON_Number of string
  | JSON_Bool of bool
  | JSON_Null

exception Syntax_error of string

val json_to_string : ?pretty:bool -> json -> string
val json_to_multiline : json -> string
val json_to_output: out_channel -> json ->  unit
val json_of_string : ?strict:bool -> string -> json
val json_of_file : ?strict:bool -> string -> json

val get_object_exn : json -> (string * json) list
val get_array_exn : json -> json list
val get_string_exn : json -> string
val get_number_exn : json -> string
val get_number_int_exn : json -> int
val get_bool_exn : json -> bool

val opt_string_to_json : string option -> json
val opt_int_to_json : int option -> json

val int_ : int -> json
val string_ : string -> json

(** Types and functions for monadic API for traversing a JSON object. *)

type json_type =
  | Object_t
  | Array_t
  | String_t
  | Number_t
  | Integer_t
  | Bool_t

(**
 * This module gives monadic recursive access to values within objects by key.
 * It uses the Result.t to manage control flow in the monad when an error is
 * encountered. It also tracks the backtrace of the keys accessed to give
 * detailed error messages.
 *
 * Usage:
 *  To access the boolean value "qux" from the following json:
   *  { "foo": { "bar" : { "baz" : { "qux" : true } } } }
 * Is as follows:
   * (return json) >>=
   *   get_obj "foo" >>=
   *   get_obj "bar" >>=
   *   get_obj "baz" >>=
   *   get_bool "qux"
 *
 * If an error is encountered along the call chain, a Result.Error is returned
 * with the appropriate error and the history of key accesses that arrived
 * there (so you can trace how far it went successfully and exactly where the
 * error was encountered).
 *
 * Same goes for accessing multiple fields within one object.
 * Suppose we have a record type:
   *  type fbz_record = {
   *    foo : bool;
   *    bar : string;
   *    baz : int;
   *  }
 *
 * And we have JSON as a string:
   * let data =
   *    "{\n"^
   *    "  \"foo\" : true,\n"^
   *    "  \"bar\" : \"hello\",\n"^
   *    "  \"baz\" : 5\n"^
   *    "}"
   * in
 *
 * We parse the JSON, monadically access the fields we want, and fill in the
 * record by doing:
 *
   *  let json = Hh_json_json_of_string data in
   *  let open Hh_json.Access in
   *  let accessor = return json in
   *  let result =
   *    accessor >>= get_bool "foo" >>= fun (foo, _) ->
   *    accessor >>= get_string "bar" >>= fun (bar, _) ->
   *    accessor >>= get_number_int "baz" >>= fun (baz, _) ->
   *    return {
   *      foo;
   *      bar;
   *      baz;
   *    }
   *  in
 *
 * The result will be the record type inside the Result monad.
 *
   * match result with
   * | Result.Ok (v, _) ->
   *   Printf.eprintf "Got baz: %d" v.baz
   * | Result.Error access_failure ->
   *   Printf.eprintf "JSON failure: %s"
   *     (access_failure_to_string access_failure)
 *
 * See unit tests for more examples.
*)
module type Access = sig
  type keytrace = string list

  type access_failure =
    | Not_an_object of keytrace (** You can't access keys on a non-object JSON thing. *)
    | Missing_key_error of string * keytrace (** The key is missing. *)
    | Wrong_type_error of keytrace * json_type (** The key has the wrong type. *)

  (** Our type for the result monad. It isn't just the json because it tracks
   * a history of the keys traversed to arrive at the current point. This helps
   * produce more informative error states. *)
  type 'a m = (('a * keytrace), access_failure) Hack_result.t

  val access_failure_to_string : access_failure -> string

  val return : 'a -> 'a m

  val (>>=) : 'a m -> (('a * keytrace) -> 'b m) -> 'b m

  (** This is a comonad, but we need a little help to deal with failure *)
  val counit_with : (access_failure -> 'a) -> 'a m -> 'a

  (**
   * The following getters operate on a JSON_Object by accessing keys on it,
   * and asserting the returned value has the given expected type (types
   * are asserted by which getter you choose to use).
   *
   * Returns Not_an_object if the given JSON object is not a JSON_Object type,
   * since you can only access keys on those.
   *
   * Returns Wrong_type_error if the obtained value is not an object type.
   *
   * Returns Missing_key_error if the given key is not found in this object.
   *
  *)
  val get_obj : string -> json * keytrace -> json m
  val get_bool : string -> json * keytrace -> bool m
  val get_string : string -> json * keytrace -> string m
  val get_number : string -> json * keytrace -> string m
  val get_number_int : string -> json * keytrace -> int m
  val get_array: string -> json * keytrace -> (json list) m
  val get_val: string -> json * keytrace -> json m (* any expected type *)
end

module Access : Access
