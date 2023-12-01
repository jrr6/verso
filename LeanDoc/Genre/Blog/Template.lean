import Lean

import LeanDoc.Doc
import LeanDoc.Doc.Html
import LeanDoc.Genre.Blog.Basic
import LeanDoc.Genre.Blog.Site
import LeanDoc.Html

open Lean (RBMap)

open LeanDoc Doc Html
open LeanDoc.Genre Blog

private def next (xs : Array α) : Option (α × Array α) :=
  if _ : 0 < xs.size then
    some (xs[0], xs.extract 1 xs.size)
  else
    none

instance [Monad m] : MonadPath (HtmlT Blog m) where
  currentPath := do
    let (_, ctxt, _) ← read
    pure ctxt.path

instance [Monad m] : MonadConfig (HtmlT Blog m) where
  currentConfig := do
    let (_, ctxt, _) ← read
    pure ctxt.config

open HtmlT

defmethod Highlighted.Token.Kind.«class» : Highlighted.Token.Kind → String
  | .var .. => "var"
  | .sort .. => "sort"
  | .const .. => "const"
  | .keyword .. => "keyword"
  | .unknown => "unknown"

defmethod Highlighted.Token.toHtml (tok : Highlighted.Token) : Html := {{
  {{tok.pre}}<span class={{tok.kind.«class»}}>{{tok.content}}</span>{{tok.post}}
}}

defmethod Highlighted.Span.Kind.«class» : Highlighted.Span.Kind → String
  | .info => "info"
  | .warning => "warning"
  | .error => "error"

partial defmethod Highlighted.toHtml : Highlighted → Html
  | .token t => t.toHtml
  | .span s hl => {{<span class={{s.«class»}}>{{toHtml hl}}</span>}}
  | .seq hls => hls.map toHtml

partial instance : GenreHtml Blog IO where
  part _ m := nomatch m
  block _go
    | .highlightedCode hls, _contents => do
      pure {{ <pre class="hl lean"> {{ hls.toHtml }} </pre> }}
  inline go
    | .label x, contents => do
      let contentHtml ← contents.mapM go
      let some tgt := (← state).targets.find? x
        | panic! "No label for {x}"
      pure {{ <span id={{tgt.htmlId}}> {{ contentHtml }} </span>}}
    | .ref x, contents => do
      match (← state).targets.find? x with
      | none =>
        HtmlT.logError "Can't find target {x}"
        pure {{<strong class="internal-error">s!"Can't find target {x}"</strong>}}
      | some tgt =>
        let addr := s!"{String.join ((← relative tgt.path).intersperse "/")}#{tgt.htmlId}"
        go <| .link contents (.url addr)
    | .pageref x, contents => do
      match (← state).pageIds.find? x with
      | none =>
        HtmlT.logError "Can't find target {x}"
        pure {{<strong class="internal-error">s!"Can't find target {x}"</strong>}}
      | some path =>
        let addr := String.join ((← relative path).intersperse "/")
        go <| .link contents (.url addr)

namespace LeanDoc.Genre.Blog.Template

structure Params.Val where
  value : Dynamic
  fallback : Array Dynamic

namespace Params.Val

def get? [TypeName α] (value : Val) : Option α :=
  value.value.get? α <|> do
    for v in value.fallback do
      if let some x := v.get? α then return x
    none

def getD [TypeName α] (value : Val) (default : α) : α :=
  value.get? |>.getD default

end Params.Val

deriving instance TypeName for String


instance : Coe String Template.Params.Val where
  coe str := ⟨.mk str, #[.mk <| Html.text str]⟩

instance : Coe Html Template.Params.Val where
  coe
   | .text str => ↑str
   | other => ⟨.mk other, #[]⟩


def Params := RBMap String Params.Val compare


namespace Params

def ofList (params : List (String × Val)) : Params :=
  Lean.RBMap.ofList params

def toList (params : Params) : List (String × Val) :=
  Lean.RBMap.toList params

def insert (params : Params) (key : String) (val : Val) : Params :=
  Lean.RBMap.insert params key val


end Params

inductive Error where
  | missingParam (param : String)
  | wrongParamType (param : String) (type : Lean.Name)

structure Context where
  site : Site
  config : Config
  path : List String
  params : Params

end Template

abbrev TemplateM (α : Type) : Type := ReaderT Template.Context (Except Template.Error) α

abbrev Template := TemplateM Html

instance : MonadPath TemplateM where
  currentPath := Template.Context.path <$> read

instance : MonadConfig TemplateM where
  currentConfig := Template.Context.config <$> read

namespace Template

def param? [TypeName α] (key : String) : TemplateM (Option α) := do
  match (← read).params.find? key with
  | none => return none
  | some val =>
    if let some v := val.get? (α := α) then return (some v)
    else throw <| .wrongParamType key (TypeName.typeName α)


def param [TypeName α] (key : String) : TemplateM α := do
  match (← read).params.find? key with
  | none => throw <| .missingParam key
  | some val =>
    if let some v := val.get? (α := α) then return v
    else throw <| .wrongParamType key (TypeName.typeName α)

namespace Params

end Params
