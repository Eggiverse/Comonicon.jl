using .Types: CommandDoc
using DataStructures
"""
    PoptartCtx

Poptart code generation context.
"""
struct PoptartCtx <: AbstractCtx
    arg_inputs::OrderedDict{Arg, Symbol}
    option_inputs::Dict{Option, Symbol}
    flag_inputs::Dict{Flag, Symbol}
    windows::Symbol
    app::Symbol
    warning::Symbol
    help::Symbol
    version::Symbol
end

PoptartCtx() = PoptartCtx(Dict{Arg, Symbol}(), 
                          Dict{Option, Symbol}(),
                          Dict{Flag, Symbol}(), 
                          gensym(:windows),
                          gensym(:app), 
                          gensym(:warning), 
                          gensym(:help), 
                          gensym(:version))

"""
    codegen(cmd)

Generate Julia AST from given command object `cmd`. This will wrap
all the generated AST in a function `command_main`.
"""
function codegen(cmd::AbstractCommand)
    println("generation")
    defs = Dict{Symbol,Any}()
    defs[:name] = :poptart_main
    defs[:args] = []

    ctx = PoptartCtx()
    defs[:body] = quote
        $(codegen(ctx, cmd))
    end

    ret_app = gensym(:app)

    return quote
        import Poptart

        $(combinedef(defs))
        $ret_app = poptart_main()
        Poptart.Desktop.exit_on_esc() = true
        Base.JLOptions().isinteractive==0 && wait($ret_app.closenotify)
    end
end

function codegen(ctx::PoptartCtx, cmd::EntryCommand)
    quote
        # $(codegen_help(ctx, cmd.root, xprint_help(cmd)))
        # $(codegen_version(ctx, cmd.root, xprint_version(cmd)))
        $(codegen_body(ctx, cmd.root))
    end
end

function codegen_body(ctx::PoptartCtx, cmd::LeafCommand; window_index::Int=1)
    ret = Expr(:block)
    
    push!(ret.args, codegen_app(ctx, cmd), codegen_description(ctx, cmd))

    for args in (cmd.args, cmd.options, cmd.flags)
        expr = codegen_controls(ctx, args)
        push!(ret.args, expr)
    end

    button_run = gensym(:button_run)
    button_cancel = gensym(:button_cancel)

    params = gensym(:params)
    kwparams = gensym(:kwparams)

    button_expr = quote
        $button_run = Poptart.Desktop.Button(title = "run")
        $button_cancel = Poptart.Desktop.Button(title = "cancel")
        $(ctx.warning) = Poptart.Desktop.Label("")
        push!($(ctx.windows)[$window_index].items, $button_run, $button_cancel, $(ctx.warning))

        Poptart.Desktop.didClick($button_run) do event
            $(ctx.warning).text = ""
            try
                $(codegen_params(ctx, params, kwparams, cmd))
                $(codegen_call(ctx, params, kwparams, cmd))
            catch e
                $(ctx.warning).text = string(e)
            end
        end
        Poptart.Desktop.didClick($button_cancel) do event
            exit(1)
        end
    end
    push!(ret.args, button_expr)

    push!(ret.args, :(return $(ctx.app)))
    return ret
end

function codegen_app(ctx::PoptartCtx, cmd::LeafCommand)
    quote
        $(ctx.windows) = [Poptart.Desktop.Window(title=$(cmd.name))]
        $(ctx.app) = Poptart.Desktop.Application(windows=$(ctx.windows))
    end
end

function codegen_description(ctx::PoptartCtx, cmd::LeafCommand; window_index::Int=1)
    :(push!($(ctx.windows)[$window_index].items, Poptart.Desktop.Label($(cmd.doc.first)), Poptart.Desktop.Separator()))
end

function codegen_params(ctx::PoptartCtx, params::Symbol, kwparams::Symbol, cmd::LeafCommand)
    hasparameters(cmd) || return
    args = gensym(:args)
    arg = gensym(:arg)

    ret = quote
        $params = []
        $args = $(xget_args(ctx, ctx.arg_inputs))
        for $arg in $args
            if $arg === ""
                break
            end
            push!($params, $arg)
        end
        $kwparams = []
        $args = $(xget_kwargs(ctx, ctx.option_inputs))
        for $arg in $args
            if $arg.second === ""
                continue
            end
            push!($kwparams, $arg)
        end
        $args = $(xget_kwargs(ctx, ctx.flag_inputs))
        for $arg in $args
            push!($kwparams, $arg)
        end
    end
    ret
end

function xget_args(ctx::PoptartCtx, arg_inputs)
    ret = Expr(:vect)
    for (arg, input) in arg_inputs
        value = inputvalue(ctx, arg, input)
        push!(ret.args, value)
    end
    ret
end

function xget_kwargs(ctx::PoptartCtx, arg_inputs)
    ret = :(Dict())
    for (arg, input) in arg_inputs
        value = inputvalue(ctx, arg, input)
        push!(ret.args, :($(QuoteNode(cmd_sym(arg))) => $value))
    end
    ret
end

function codegen_call(::PoptartCtx, params::Symbol, kwparams::Symbol, cmd::LeafCommand)
    ex_call = Expr(:call, cmd.entry)
    
    return :($(cmd.entry)($params...; $kwparams...))
end

function xwarn(ctx::PoptartCtx, message::AbstractString)
    :($(ctx.warning).Label = $message)
end

inputvalue(ctx::PoptartCtx, opt::Option, input::Symbol) = inputvalue(ctx, opt.arg, input)

function inputvalue(::PoptartCtx, arg::Arg, input::Symbol)
    if arg.type == Any
        value = :($input.buf)
    else
        value = :(parse($(arg.type), $input.buf))
    end
    value
end

# function inputvalue(::PoptartCtx, flag::Flag, input::Symbol)
#     :(parse(Bool, $input.buf))
# end

function inputvalue(::PoptartCtx, flag::Flag, input::Symbol)
    :($input.value)
end

function Base.push!(ctx::PoptartCtx, arg_input::Pair{Arg, Symbol})
    push!(ctx.arg_inputs, arg_input)
end

function Base.push!(ctx::PoptartCtx, arg_input::Pair{Option, Symbol})
    push!(ctx.option_inputs, arg_input)
end

function Base.push!(ctx::PoptartCtx, arg_input::Pair{Flag, Symbol})
    push!(ctx.flag_inputs, arg_input)
end

function process_default(arg::Arg)
    process_default(arg.default)
end

function process_default(opt::Option)
    process_default(opt.arg.default)
end

function process_default(::Nothing)
    (buf="", tip="")
end

function process_default(value::Number)
    (buf=string(value), tip="")
end

function process_default(value::Expr)
    (buf="", tip="\nDefault value is $value")
end

function process_label(opt::Option)
    process_label(opt.arg, opt.doc)
end

function process_label(arg::Arg)
    process_label(arg, arg.doc)
end

function process_label(flag::Flag)
    label = flag.name * "::Bool"
    doc = flag.doc
    arg_docstring = string(doc)
    if arg_docstring != ""
        label *= "\n" * arg_docstring
    end
    label
end

function process_label(arg::Arg, doc::CommandDoc)
    label = arg.name
    if arg.type != Any
        label *= "::" * string(arg.type)
    end
    if arg.require
        label *= " *"
    end
    arg_docstring = string(doc)
    if arg_docstring != ""
        label *= "\n" * arg_docstring
    end
    label
end

"""
Generate inputs for `args`
"""
function codegen_controls(ctx::PoptartCtx, args; window_index::Int=1)
    genexpr = Expr(:block)
    group = gensym(:group)
    push!(genexpr.args, quote
        $group = Poptart.Desktop.Group(items=[Poptart.Desktop.NewLine()])
        push!($(ctx.windows)[$window_index].items, $group)
    end
    )
    for arg in args
        expr, input = codegen_control(ctx, group, arg)
        push!(genexpr.args, expr)
    end
    return genexpr
end

function codegen_control(ctx::PoptartCtx, group::Symbol, arg)
    input_symbol = gensym(:input)
    expr = codegen_control(ctx, input_symbol, group, arg)
    push!(ctx, arg=>input_symbol)
    return expr, input_symbol
end


function codegen_control(ctx::PoptartCtx, input::Symbol, group::Symbol, arg::Union{Arg, Option})
    label = process_label(arg)

    buf, tip = process_default(arg)
    label *= tip

    codegen_control(ctx, input, buf; name=arg.name, label=label, group=group)
end

function codegen_control(ctx::PoptartCtx, input::Symbol, group::Symbol, flag::Flag)
    label = process_label(flag)

    codegen_control(ctx, input, false; name=flag.name, label=label, group=group)
end

function codegen_control(::PoptartCtx, input::Symbol, buf::AbstractString; name::AbstractString, label::AbstractString, group::Symbol)
    quote
        push!($group.items, Poptart.Desktop.Label($label))
        $input = Poptart.Desktop.InputText(label = $name, buf=$buf)
        push!($group.items, $input)
    end
end

function codegen_control(::PoptartCtx, input::Symbol, value::Bool; name::AbstractString, label::AbstractString, group::Symbol)
    quote
        push!($group.items, Poptart.Desktop.Label($label))
        $input = Poptart.Desktop.Checkbox(label = $name, value=$value)
        push!($group.items, $input)
    end
end