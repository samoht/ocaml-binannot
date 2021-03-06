(**************************************************************************)
(*                                                                        *)
(*  Ocamlwizard-Binannot                                                  *)
(*  Tiphaine Turpin                                                       *)
(*  Copyright 2011 INRIA Saclay - Ile-de-France                           *)
(*                                                                        *)
(*  This software is free software; you can redistribute it and/or        *)
(*  modify it under the terms of the GNU Library General Public           *)
(*  License version 2.1, with the special exception on linking            *)
(*  described in file LICENSE.                                            *)
(*                                                                        *)
(*  This software is distributed in the hope that it will be useful,      *)
(*  but WITHOUT ANY WARRANTY; without even the implied warranty of        *)
(*  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.                  *)
(*                                                                        *)
(**************************************************************************)

(** Identifying idents which cannot be renamed independently of each
    other (due to signature matching in particular). *)

(* should not be here *)
val sig_item_id : Types.signature_item -> Ident.t

type source_kind = [`ml | `mli]

(** A source file is given by its (non-capitalized) prefix and source kind. *)
type source_file = string * source_kind

(** The context for interpreting an ident is either a persistent module
    (whose name is capitalized) or a source file *)
type ident_context = [`pers of string | `source of source_file]

(** These names should be really unique. *)
type global_ident = ident_context * Ident.t

type signature = ident_context * Types.signature

module ConstraintSet : Set.S
  with type elt = signature * signature

module IncludeSet : Set.S
  with type elt = signature * Ident.t list

(*
(** Collect the set of signature inclusion constraints and include
  statements for a structure. *)
  val collect_signature_inclusions :
  (ConstraintSet.t * IncludeSet.t) TypedtreeOps.sfun
*)

(** Return the minimal set of idents which may be renamed and contains
    a given id, as well as the "implicit" bindings of signature
    elements to those idents. *)
val propagate_all_files :
  Env.t -> Env.path_sort -> Ident.t ->
  (source_file * (TypedtreeOps.typedtree * 'a * 'b * 'c * Typedtree.signature))
    list -> ConstraintSet.t * IncludeSet.t
(* means id is bound to sg.(name id), unless we were wrong about the sort. *)

val propagate :
  source_file -> Env.path_sort -> Ident.t ->
  (source_file * (TypedtreeOps.typedtree * 'a * 'b * 'c * Typedtree.signature))
    list -> ConstraintSet.t -> IncludeSet.t ->
  global_ident list
  * ([ `certain | `maybe ] * Types.signature * global_ident) list

val check_renamed_implicit_references :
  Env.path_sort -> global_ident list -> string ->
  ([ `certain | `maybe ] * Types.signature * global_ident) list -> unit

val check_other_implicit_references :
  Env.path_sort -> global_ident list -> string ->
  ConstraintSet.t -> IncludeSet.t -> unit
