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

open Util
open Lexing
open Location
open Longident
open Path
open Types
open Typedtree
open TypedtreeOps
open Resolve
open FindName
open RenameLid
open RenamePropagation

(*
(* The type of renaming conotexts, i.e., modules or module types of
   which the renamed element is a member. *)
type renaming_context =
  | Persistent of Path.t (* a flat path starting with a persistent Id *)
  | Local of Ident.t (* A "local" ident *)
*)

type toplevel_item =
  | Ml of structure
  | Mli of signature

(* Identifiers for a set of compilation units. *)
type absolute_id = toplevel_item * Ident.t (* non-persistent Id *)
type absolute_path = toplevel_item * Path.t (* maybe persistent root Id *)

(*
let rec path2lident = function
  | Pident i -> Lident (Ident.name i)
  | Pdot (p, n, _) -> Ldot (path2lident p, n)
  | Papply (p, p') -> Lapply (path2lident p, path2lident p')
*)

(*
type exp_exp =
  | Rexp_let_left of rec_flag * (pattern * expression) list * int * expression
  | Rexp_let_right of rec_flag * (pattern * expression) list
(* TODO *)
(*
  | Texp_function of label * (pattern * expression) list * partial
  | Texp_apply of expression * (label * expression option * optional) list
  | Texp_match of expression * (pattern * expression) list * partial
  | Texp_try of expression * (pattern * expression) list
  | Texp_tuple of expression list
  | Texp_construct of Path.t * constructor_description * expression list
  | Texp_variant of label * expression option
  | Texp_record of (Path.t * label_description * expression) list * expression option
  | Texp_field of expression * Path.t * label_description
  | Texp_setfield of expression * Path.t * label_description * expression
  | Texp_array of expression list
  | Texp_ifthenelse of expression * expression * expression option
  | Texp_sequence of expression * expression
  | Texp_while of expression * expression
  | Texp_for of
      Ident.t * expression * expression * direction_flag * expression
  | Texp_constraint of expression * core_type option * core_type option
  | Texp_when of expression * expression
  | Texp_send of expression * meth * expression option
  | Texp_setinstvar of Path.t * Path.t * expression
  | Texp_override of Path.t * (Path.t * expression) list
  | Texp_letmodule of Ident.t * module_expr * expression
  | Texp_assert of expression
  | Texp_lazy of expression
  | Texp_poly of expression * core_type option
  | Texp_newtype of string * expression
  | Texp_open of Path.t * expression
*)

and exp_str =
  | Rstr_eval
  | Rstr_value of rec_flag * (pattern * expression) list * int

type ident_ctx =
  | Rpat_var of pattern * pattern_ctx
  | Rstr_module of structure_item * structure_item_ctx

and pattern_ctx =
  | Rexp_let of expression * expression_ctx
  | Rexp_function of expression * expression_ctx
  | Rexp_match of expression * expression_ctx
  | Rexp_try of expression * expression_ctx
  | Rpat_alias of pattern_desc * alias_kind

and expression_ctx =
  | Rexp of expression * exp_exp
  | Rstr of structure_item * exp_str

and expression = {
  exp : Parsetree.expression
  exp_ctx : expression_ctx
}

and structure_item_ctx

let expression ctx exprs e = match e.exp_desc with
  | Texp_let (_, bindings, exp) ->
    exprs exp (Rexp_let_right (e, ctx))
  | Texp_ident _
  | Texp_constant _
  | Texp_function _
  | Texp_apply _
  | Texp_match _
  | Texp_try _
  | Texp_tuple _
  | Texp_construct _
  | Texp_variant _
  | Texp_record _
  | Texp_field _
  | Texp_setfield _
  | Texp_array _
  | Texp_ifthenelse _
  | Texp_sequence _
  | Texp_while _
  | Texp_for _
  | Texp_constraint _
  | Texp_when _
  | Texp_send _
  | Texp_new _
  | Texp_instvar _
  | Texp_setinstvar _
  | Texp_override _
  | Texp_letmodule _
  | Texp_assert _
  | Texp_assertfalse
  | Texp_lazy _
  | Texp_poly _
  | Texp_object _
  | Texp_newtype _
  | Texp_pack _
  | Texp_open _ ->  ()
*)
(*
let resolve item = function
    | Pident i -> item, i
    | Pdot (p, n, _) ->
      let item, i = resolve p in
    | Papply (p, p') -> assert false
*)


let check_lids renamed_kind id name' lids =
  List.iter
    (function _, lid, (env, kind) ->
      check_lid renamed_kind id name' env kind lid)
    lids

let rename_lids renamed_kind id name' lids =
  List.fold_left (* this is a filter_map *)
    (fun l (loc, lid, (env, kind)) ->
      match rename_in_lid renamed_kind id name' env kind lid with
	| Some lid ->
	  (loc.loc_start.pos_cnum, loc.loc_end.pos_cnum, Util.lid_to_str lid)
	  :: l
	| None -> l)
    []
    (List.rev lids)

let classify_source f =
  let open Filename in
    if
      check_suffix f ".ml" then `ml
    else if
      check_suffix f ".mli" then `mli
    else
      invalid_arg "not an OCaml source file"

let typedtree_file source_kind f =
  Filename.chop_extension f ^
    match source_kind with
      | `ml -> ".cmt"
      | `mli -> ".cmti"

let read_typedtree _ file =
  let c = open_in file in
  let data = input_value c in
    close_in c;
    let tree =
      match data.(0) with
	| Saved_implementation str -> `structure str
	| Saved_signature sg -> `signature sg
	| _ -> fail_owz "error reading cmt(i) file"
    in
      try
	match data.(1), data.(2), data.(3) with
	  | Saved_ident_locations (Some loc),
	    Saved_longident_locations (Some lloc),
	    Saved_path_environments (Some env) ->
	      tree, loc, lloc, env
	  | _ -> raise Not_found
      with
	  _ -> fail_owz
	    "ident location or path environment table not found in cmt(i)"

let sort_replaces =
  List.sort
    (fun (x, _, _) (y, _, _) -> compare  x y)

let find_id_defs ids name s =
  List.fold_right
    (fun id acc ->
      try
	let loc = find_id_def s id in
	(loc.loc_start.pos_cnum, loc.loc_end.pos_cnum, name) :: acc
      with
	  Not_found -> acc)
    ids
    []
(*
 [fst loc, snd loc, name']
*)

let fix_case kind =
  match kind with
    | Env.Module | Env.Modtype | Env.Constructor -> String.capitalize
    | _ -> String.uncapitalize

let backup file =
  let backup = file ^ ".backup_" ^ string_of_int (int_of_float (Unix.time ())) in
    if Sys.file_exists backup then
      failwith "bad luck"
    else
      Edit.cp file backup

(* Rename an ident in a structure file, with given ast. *)
let rename_in_file
    env renamed_kind id name' file (typedtree, idents, lid2loc, paths) =

  (* Collect constraints requiring simultaneous renaming *)
  let constraints, includes = collect_signature_inclusions typedtree in

  (* Deduce the minimal set of ids to rename *)
  let ids, implicit_refs =
    propagate_renamings renamed_kind id constraints includes in

  (* Compute the replacements for the *definitions* of the rename ids *)
  let def_replaces = find_id_defs ids name' idents in

  (* Check that our new name will not capture useful signature members *)
  check_other_implicit_references renamed_kind ids name' constraints includes;

  (* Check that useful renamed signature members are not masked. *)
  check_renamed_implicit_references renamed_kind ids name' implicit_refs;

  (* Collect all lids *)
  let lids = get_lids env file lid2loc paths typedtree in

  (* Check that our new name will not capture other occurrences *)
  check_lids renamed_kind ids name' lids;

  (* Compute renamed lids, checking that they are not captured *)
  let occ_replaces = rename_lids renamed_kind ids name' lids in

  def_replaces, occ_replaces 

(* Renaming entry point: user interface... *)
let rename loc name' file =

  backup file;

  (* Setup the environment *)
  let dirs = Common_config.search_dirs file in
  Config.load_path := "" :: List.rev_append dirs (Clflags.std_include_dir ());
  let env = initial_env () in (* Make sure that Pervasives is loaded *)
  debugln "load_path:"; List.iter (debugln "  %s") !Config.load_path;

  (* Check that everything is up-to-date *)
  if Common_config.has_auto_save file then
    fail_owz "buffer must be saved before renaming";
  let source_kind = classify_source file in
  let typedtree_file = typedtree_file source_kind file in
  if not (Sys.file_exists typedtree_file) then
    fail_owz "no cmt(i) file for %s" file;
  if Unix.((stat file).st_mtime > (stat typedtree_file).st_mtime) then
    fail_owz "cmt(i) file is older than source file";

  (* Read the typedtree *)
  let s, idents, lidents, paths = read_typedtree source_kind typedtree_file in

  (* Get the "initial" id to rename and its sort *)
  let renamed_kind, id = locate_renamed_id s loc in
  let name = Ident.name id in

  let name' = fix_case renamed_kind name' in

  try
    let def_replaces, occ_replaces =
      rename_in_file env renamed_kind id name' file (s, idents, lidents, paths)
    in

    (* We need to sort them again (they may interleave). *)
    let replaces = sort_replaces (def_replaces @ occ_replaces) in

    (* Replace lids in the source file *)
    Edit.edit replaces file;

    Printf.printf "Renamed %d definition(s) and %d reference(s)"
      (List.length def_replaces) (List.length occ_replaces)
  with
      Masked_by (renamed, id) ->
	let loc = find_id_def idents id in
	  Location.print Format.std_formatter loc;
	  if renamed then
	    fail_owz
	      "This existing definition of %s would capture an occurrence of %s"
	      name' name
	  else
	    fail_owz
	      "This definition of %s that you are trying to rename would \
                 capture an occurrence of an existing definition of %s"
	      name name'