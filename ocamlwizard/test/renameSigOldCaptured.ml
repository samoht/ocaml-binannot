(* An occurrence of the old name would be captured if we rename it. *)
module M = struct
  let $x€ = 1
  let y = ()
end

let _ = M.x
