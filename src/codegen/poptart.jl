using .Types: CommandDoc
"""
    PoptartCtx

Poptart code generation context.
"""
struct PoptartCtx <: AbstractCtx
    arg_inputs::Dict{Arg, Symbol}
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
    defs = Dict{Symbol,Any}()
    defs[:name] = :poptart_main
    defs[:args] = []

    ctx = PoptartCtx()
    defs[:body] = quote
        $(codegen(ctx, cmd))
    end

    return quote
        import Poptart
        $(ctx.windows) = [Poptart.Desktop.Window(title=$(cmd.root.name))]
        $(ctx.app) = Poptart.Desktop.Application(windows=$(ctx.windows))
        $(combinedef(defs))
        poptart_main()
        Poptart.Desktop.exit_on_esc() = true
        Base.JLOptions().isinteractive==0 && wait($(ctx.app).closenotify)
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
    
    push!(ret.args, code_gendescription(ctx, cmd))

    for args in (cmd.args, cmd.options, cmd.flags)
        expr = codegen_inputs(ctx, args)
        push!(ret.args, expr)
    end

    button_run = gensym(:button_run)
    button_cancel = gensym(:button_cancel)

    button_expr = quote
        $button_run = Poptart.Desktop.Button(title = "run")
        $button_cancel = Poptart.Desktop.Button(title = "cancel")
        push!($(ctx.windows)[$window_index].items, $button_run, $button_cancel)

        Poptart.Desktop.didClick($button_run) do event
            $(codegen_call(ctx, cmd))
        end
        Poptart.Desktop.didClick($button_cancel) do event
            exit(1)
        end
    end
    push!(ret.args, button_expr)

    push!(ret.args, :(return 0))
    return ret
end

function code_gendescription(ctx::PoptartCtx, cmd::LeafCommand; window_index::Int=1)
    :(push!($(ctx.windows)[$window_index].items, Poptart.Desktop.Label($(cmd.doc.first) * "\n ")))
end

function codegen_call(ctx::PoptartCtx, cmd::LeafCommand)
    ex_call = Expr(:call, cmd.entry)
    
    for (arg, input) in ctx.arg_inputs
        value = inputvalue(ctx, arg, input)
        push!(ex_call.args, value)
    end

    for (opt, input) in ctx.option_inputs
        value = inputvalue(ctx, opt.arg, input)
        push!(ex_call.args, Expr(:kw, Symbol(opt.name), value))
    end

    for (flag, input) in ctx.flag_inputs
        value = :(parse(Bool, $input.buf))
        push!(ex_call.args, Expr(:kw, Symbol(flag.name), value))
    end
    
    return ex_call
end

function xwarn(ctx::PoptartCtx, message::AbstractString)
    :($(ctx.warning).Label = $message)
end

function inputvalue(::PoptartCtx, arg::Arg, input::Symbol)
    if arg.type == Any
        value = :($input.buf)
    else
        value = :(parse($(arg.type), $input.buf))
    end
    value
end

"""
Generate inputs for `args`
"""
function codegen_inputs(ctx::PoptartCtx, args)
    genexpr = Expr(:block)
    for arg in args
        expr, input = codegen_input(ctx, arg)
        push!(genexpr.args, expr)
    end
    return genexpr
end

function codegen_input(ctx::PoptartCtx, arg)
    input_symbol = gensym(:input)
    expr = codegen_input(ctx, input_symbol, arg)
    push!(ctx, arg=>input_symbol)
    return expr, input_symbol
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

function codegen_input(ctx::PoptartCtx, input::Symbol, arg::Arg; window_index::Int=1)
    label = process_label(arg)

    buf, tip = process_default(arg)
    label *= tip
    quote
        push!($(ctx.windows)[$window_index].items, Poptart.Desktop.Label($label))
        $input = Poptart.Desktop.InputText(label = $(arg.name), buf=$buf)
        push!($(ctx.windows)[$window_index].items, $input)
    end
end

function codegen_input(ctx::PoptartCtx, input::Symbol, opt::Option; window_index::Int=1)
    label = process_label(opt)
    buf, tip = process_default(opt)
    label *= tip
    quote
        push!($(ctx.windows)[$window_index].items, Poptart.Desktop.Label($label))
        $input = Poptart.Desktop.InputText(label = $(opt.name), buf=$buf)
        push!($(ctx.windows)[$window_index].items, $input)
    end
end

function codegen_input(ctx::PoptartCtx, input::Symbol, flag::Flag; window_index::Int=1)
    label = process_label(flag)

    quote
        push!($(ctx.windows)[$window_index].items, Poptart.Desktop.Label($label))
        $input = Poptart.Desktop.InputText(label = $(flag.name), buf="false")
        push!($(ctx.windows)[$window_index].items, $input)
    end
end
