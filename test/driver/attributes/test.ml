open Ppxlib

let () = Driver.enable_checks ()

let loc = Location.none
[%%expect{|
val loc : location =
  {Ppxlib.Location.loc_start =
    {Lexing.pos_fname = "_none_"; pos_lnum = 1; pos_bol = 0; pos_cnum = -1};
   loc_end =
    {Lexing.pos_fname = "_none_"; pos_lnum = 1; pos_bol = 0; pos_cnum = -1};
   loc_ghost = true}
|}]

let x = 1 [@@foo]
[%%expect{|
Line _, characters 13-16:
Error: Attribute `foo' was not used
|}]

let f x = 1 [@@deprecatd "..."]
[%%expect{|
Line _, characters 15-24:
Error: Attribute `deprecatd' was not used.
       Hint: Did you mean deprecated?
|}]

let attr : _ Attribute.t =
  Attribute.declare "blah"
    Attribute.Context.type_declaration
    Ast_pattern.(__)
    ignore
[%%expect{|
val attr : (type_declaration, unit) Attribute.t = <abstr>
|}]

type t = int [@blah]
[%%expect{|
Line _, characters 15-19:
Error: Attribute `blah' was not used.
       Hint: `blah' is available for type declarations but is used here in
       the
       context of a core type.
       Did you put it at the wrong level?
|}]

let attr : _ Attribute.t =
  Attribute.declare "blah"
    Attribute.Context.expression
    Ast_pattern.(__)
    ignore
[%%expect{|
val attr : (expression, unit) Attribute.t = <abstr>
|}]

type t = int [@blah]
[%%expect{|
Line _, characters 15-19:
Error: Attribute `blah' was not used.
       Hint: `blah' is available for expressions and type declarations but is
       used
       here in the context of a core type.
       Did you put it at the wrong level?
|}]

let _ = () [@blah]
[%%expect{|
Line _, characters 13-17:
Error: Attribute `blah' was not used
|}]

(* Attribute drops *)

let faulty_transformation = object
  inherit Ast_traverse.map as super

  method! expression e =
    match e.pexp_desc with
    | Pexp_constant c ->
      Ast_builder.Default.pexp_constant ~loc:e.pexp_loc c
    | _ -> super#expression e
end
[%%expect{|
val faulty_transformation : Ast_traverse.map = <obj>
|}]

let () =
  Driver.register_transformation "faulty" ~impl:faulty_transformation#structure

let x = (42 [@foo])
[%%expect{|
Line _, characters 14-17:
Error: Attribute `foo' was silently dropped
|}]

type t1 = < >
type t2 = < t1 >
type t3 = < (t1[@foo]) >
[%%expect{|
type t1 = <  >
type t2 = <  >
Line _, characters 17-20:
Error: Attribute `foo' was not used
|}]

(* Reserved Namespaces *)

(* ppxlib checks that unreserved attributes aren't dropped *)

let x = (42 [@bar])
[%%expect{|
Line _, characters 14-17:
Error: Attribute `bar' was silently dropped
|}]

let x = (42 [@bar.baz])
[%%expect{|
Line _, characters 14-21:
Error: Attribute `bar.baz' was silently dropped
|}]

(* But reserving a namespace disables those checks. *)

let () = Reserved_namespaces.reserve "bar"

let x = (42 [@bar])
let x = (42 [@bar.baz])
[%%expect{|
val x : int = 42
val x : int = 42
|}]

let x = (42 [@bar_not_proper_sub_namespace])
[%%expect{|
Line _, characters 14-42:
Error: Attribute `bar_not_proper_sub_namespace' was silently dropped
|}]

(* The namespace reservation process understands dots as namespace
   separators. *)

let () = Reserved_namespaces.reserve "baz.qux"

let x = (42 [@baz])
[%%expect{|
Line _, characters 14-17:
Error: Attribute `baz' was silently dropped
|}]

let x = (42 [@baz.qux])
[%%expect{|
val x : int = 42
|}]

let x = (42 [@baz.qux.quux])
[%%expect{|
val x : int = 42
|}]

let x = (42 [@baz.qux_not_proper_sub_namespace])
[%%expect{|
Line _, characters 14-46:
Error: Attribute `baz.qux_not_proper_sub_namespace' was silently dropped
|}]

(* You can reserve multiple subnamespaces under the same namespace *)

let () = Reserved_namespaces.reserve "baz.qux2"

let x = (42 [@baz.qux])
let x = (42 [@baz.qux2])
[%%expect{|
val x : int = 42
val x : int = 42
|}]

let x = (42 [@baz.qux3])
[%%expect{|
Line _, characters 14-22:
Error: Attribute `baz.qux3' was silently dropped
|}]

(* [eta_reduce] respects attributes. *)

let run_eta_reduce expr =
  match Ast_builder.Default.eta_reduce expr with
  | None -> "No reduction"
  | Some expr ->
      ignore (Format.flush_str_formatter () : string);
      Format.fprintf Format.str_formatter "reduced: %a" Pprintast.expression
        expr;
      Format.flush_str_formatter ()
[%%expect{|
val run_eta_reduce : expression -> string = <fun>
|}]

let basic1 = run_eta_reduce [%expr fun x y -> f x y]
[%%expect{|
val basic1 : string = "reduced: f"
|}]

let basic2 = run_eta_reduce [%expr fun x y -> (f x) y]
[%%expect{|
val basic2 : string = "reduced: f"
|}]

let attributes_block_reduction1 =
  run_eta_reduce [%expr fun [@attr] x y -> f x y]
[%%expect{|
val attributes_block_reduction1 : string = "No reduction"
|}]

let attributes_block_reduction2 =
  run_eta_reduce [%expr fun x y -> (f x [@attr]) y]
[%%expect{|
val attributes_block_reduction2 : string = "No reduction"
|}]

(* See the definition of eta_reduce for what attributes are considered
 * erasable; "jane.erasable" is but a representative example. *)
let erasable_attributes_don't_block_reduction1 =
  run_eta_reduce [%expr fun [@jane.erasable] x y -> f x y]
[%%expect{|
val erasable_attributes_don't_block_reduction1 : string = "reduced: f"
|}]

let erasable_attributes_don't_block_reduction2 =
  run_eta_reduce [%expr fun x y -> (f x [@jane.erasable.foo]) y]
[%%expect{|
val erasable_attributes_don't_block_reduction2 : string = "reduced: f"
|}]
