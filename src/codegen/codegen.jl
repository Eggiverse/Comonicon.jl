module CodeGen

using ExprTools
using MatchCore
using Comonicon.Types
using Poptart.Desktop

export ASTCtx, ZSHCompletionCtx
export codegen, rm_lineinfo, prettify, pushmaybe!

abstract type AbstractCtx end

"""
    codegen(ctx, cmd)

Generate target code according to given context `ctx` from a command object `cmd`.
"""
function codegen(::AbstractCtx, ::AbstractCommand) end

include("utils.jl")
include("poptart.jl")
include("ast.jl")
include("completion.jl")

end
