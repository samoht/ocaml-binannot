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

(** Different sort of names, and their bindings. *)

val kind2str : Env.path_sort -> string

val parse_lid : Env.path_sort -> string -> Longident.t

(* not used outside Resolve
val lookup : Env.path_sort -> Longident.t -> Env.t -> Path.t
val sig_item : Env.path_sort -> Types.signature_item -> Ident.t option
val summary_item : ...
*)

(* Turns Not_found into a Failure with the unbound name *)
val wrap_lookup : ('a -> string) -> string -> ('a -> 'b -> 'c) -> 'a -> 'b -> 'c

(** Raised by modtype, modtype_signature, and modtype_functor when
    looking for the signature of an abstract module type. *)
exception Abstract_modtype

(** Get the signature (or functor signature) corresponding to a module type *)
val modtype :
  Env.t -> Types.module_type ->
  [ `func of Ident.t * Types.module_type * Types.module_type
  | `sign of Types.signature ]

(** Same thing, but we keep track of the top-level module in which the
    paths should be interpreted. *)
val modtype' :
  ([> `pers of string ] as 'a) -> Env.t -> Types.module_type ->
  'a *
    [ `func of Ident.t * Types.module_type * Types.module_type
    | `sign of Types.signature ]

(** Same as modtype, but the result must be a signature. *)
val modtype_signature : Env.t -> Types.module_type -> Types.signature

(** Same as modtype, but the result must be a functor. *)
val modtype_functor :
  Env.t -> Types.module_type ->
  Ident.t * Types.module_type * Types.module_type

(* Unused outside of this module
(** See modtype_signature. *)
val resolve_module : Env.t -> Path.t -> Types.signature
val resolve_module_lid : Env.t -> Longident.t -> Types.signature

(** See modtype. *)
val resolve_modtype :
  Env.t ->
  Path.t ->
  [ `func of Ident.t * Types.module_type * Types.module_type
  | `sign of Types.signature ]

*)

(** [resolves_to kind env lid ids] tests whether a lid reffers to one
    of ids in environment env, i.e., if the object directly denoted by
    lid is named with one of ids. This indicates that the rightmost
    name in lid needs renaming (assuming we are renaming ids). *)
val resolves_to : Env.path_sort -> Env.t -> Longident.t -> Ident.t list -> bool

(** Retrieve a module or modtype in a signature from its name *)
val lookup_in_signature :
  Env.path_sort -> string -> Types.signature -> Types.signature_item

(** Retrieve an element in a signature from its name *)
val find_in_signature :
  Env.path_sort -> string -> Types.signature -> Ident.t

(** Raised by check to signal an impossible renaming due to a masking
    of an existing occurrence of the new name, or of a renamed
    occurrence (the boolean specifies if it is a renamed occurrence). *)
exception Masked_by of bool * Ident.t

(** Check that the renaming of a list of idents (with the same name)
    into a new name would not change the meaning of a reference in a
    given environment, i.e., this reference being either one of the
    ids, or a different existing id already named with the new name,
    as denoted by the boolean renamed.

    In other words, if renamed is true, this function ensures that the
    new name will indeed reffer to one of the ids, and otherwise, that
    the existing instance of the new name will not.

    Raise Not_found if none of the given idents or name is in the
    environment.

    Raise (Masked_by id) if masking would occur. *)
val check :
  Env.path_sort -> Ident.t list -> string -> Env.t -> Env.summary ->
  renamed:bool -> unit

(** Similar to check, but for a signature. *)
val check_in_sig :
  Env.path_sort -> Ident.t list -> string -> Types.signature ->
  renamed:bool -> unit

(** Test if an id belongs to a list of ids *)
val is_one_of : Ident.t -> Ident.t list -> bool
