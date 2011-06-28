open Path
open Types
open Env
open Util

type sort = [
  | `Module
  | `Modtype
  | `Value
]

type specifics = {
  sort : sort;
  lookup : Longident.t -> Env.t -> Path.t;
  sig_item : Types.signature_item -> Ident.t option;
  summary_item : Env.summary -> Ident.t option
}

let keep_first f lid env = fst (f lid env)

let value_ops = {
  sort = `Value;
  lookup = keep_first Env.lookup_value;
  sig_item = (function Sig_value (i, _) -> Some i | _ -> None);
  summary_item = function Env_value (_, i, _) -> Some i | _ -> None
}

let module_ops = {
  sort = `Module;
  lookup = keep_first Env.lookup_module;
  sig_item = (function Sig_module (i, _, _) -> Some i | _ -> None);
  summary_item = function Env_module (_, i, _) -> Some i | _ -> None
}

let sig_item_ops = function
  | Sig_value _ -> value_ops
  | Sig_module _ -> module_ops
  | Sig_type _
  | Sig_exception _
  | Sig_modtype _
  | Sig_class _
  | Sig_class_type _ ->
    assert false

(* Return the signature of a given (extended) module type path *)
let rec resolve_modtype env path =
  match Env.find_modtype path env with
  | Modtype_abstract -> invalid_arg "resolve_mod_type"
  | Modtype_manifest mt -> modtype env mt

and modtype env = function
  | Mty_ident p -> resolve_modtype env p
  | Mty_signature s -> `sign s
  | Mty_functor (id, t, t') -> `func (id, t, t')


let modtype_signature env m =
  match modtype env m with
  | `sign s -> s
  | `func _ -> invalid_arg "modtype_signature"

let modtype_functor env m =
  match modtype env m with
  | `func f -> f
  | `sign _ -> invalid_arg "modtype_signature"

(* Return the signature of a given (extended) module path *)
let resolve_module env path =
  modtype_signature env (Env.find_module path env)

let is_one_of id = List.exists (Ident.same id)

(* True if p.name means id *)
let field_resolves_to kind env path name ids =
  name = Ident.name (List.hd ids) && (* only an optimisation *)
  List.exists
    (function s ->
      match kind.sig_item s with
	| Some id -> Ident.name id = name && is_one_of id ids
	| None -> false)
    (resolve_module env path)

(* Test whether a p reffers to id in environment env. This indicates
   that the rightmost name in lid needs renaming. *)
let resolves_to kind env lid ids =
  match kind.lookup lid env with
    | Pident id' -> is_one_of id' ids
    | Pdot (p, n, _) -> field_resolves_to kind env p n ids
    | Papply _ -> invalid_arg "resolves_to"

exception Not_masked
exception Masked_by of Ident.t

(* Check that the renaming of one of ids in name is not masked in the env. *)
let check_in_sig kind ids name sg =
  List.iter
    (function item ->
      (match kind.sig_item item with
	| Some id' ->
	  debugln "found %s" (Ident.name id');
	  if is_one_of id' ids then
	    raise Not_masked
	  else if Ident.name id' = name then
	    raise (Masked_by id')
	| None -> ()))
    (List.rev sg);
  invalid_arg "ckeck_in_sig"

(* Check that the renaming of one of ids in name is not masked in the env. *)
let rec check kind ids name env = function
  | Env_empty -> raise Not_found
  | Env_open (s, p) ->
    let sign = resolve_module env p in
    check_in_sig kind ids name sign;
    check kind ids name env s
  | summary ->
    (match kind.summary_item summary with
      | Some id' ->
	if is_one_of id' ids then
	  raise Not_masked
	else if Ident.name id' = name then
	  raise (Masked_by id')
      | None -> ());
    match summary with
      | Env_value (s, _, _)
      | Env_type (s, _, _)
      | Env_exception (s, _, _)
      | Env_module (s, _, _)
      | Env_modtype (s, _, _)
      | Env_class (s, _, _)
      | Env_cltype (s, _, _)
	-> check kind ids name env s
      | Env_open _ | Env_empty _ -> assert false

let check kind id name env summary =
  try
    ignore (check kind id name env summary);
    assert false
  with
      Not_masked -> ()

let check_in_sig kind id name sg =
  debugln "check_in_sig %s %s" (Ident.name (List.hd id)) name;
  try
    ignore (check_in_sig kind id name sg);
    assert false
  with
      Not_masked -> ()
