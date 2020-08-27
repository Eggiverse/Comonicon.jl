
"""
    PoptartCtx

Poptart code generation context.
"""
struct PoptartCtx <: AbstractCtx
    arg_inputs::Dict{Arg, Symbol}
    option_inputs::Dict{Option, Symbol}
    flag_inputs::Dict{Flag, Symbol}
    help::Symbol
    version::Symbol
end

PoptartCtx() = PoptartCtx(Dict{Arg, Symbol}(), Dict{Option, Symbol}(), Dict{Flag, Symbol}(), gensym(:help), gensym(:version))

"""
    codegen(cmd)

Generate Julia AST from given command object `cmd`. This will wrap
all the generated AST in a function `command_main`.
"""
function codegen(cmd::AbstractCommand)
    defs = Dict{Symbol,Any}()
    defs[:name] = :command_main
    defs[:args] = []

    ctx = PoptartCtx()
    defs[:body] = quote
        $(codegen(ctx, cmd))
    end
    return quote
        using Poptart.Desktop
        window = Window(title=$(cmd.root.name))
        app = Application(windows = [window])
        $(combinedef(defs))
        command_main()
        Desktop.exit_on_esc() = true
        Base.JLOptions().isinteractive==0 && wait(app.closenotify)
    end
end

function codegen(ctx::PoptartCtx, cmd::EntryCommand)
    quote
        # $(codegen_help(ctx, cmd.root, xprint_help(cmd)))
        # $(codegen_version(ctx, cmd.root, xprint_version(cmd)))
        $(codegen_body(ctx, cmd.root))
    end
end

function codegen_body(ctx::PoptartCtx, cmd::LeafCommand)
    ret = Expr(:block)
    
    for args in (cmd.args, cmd.options, cmd.flags)
        expr = codegen_inputs(ctx, args)
        push!(ret.args, expr)
    end

    button_expr = quote
        button_run = Button(title = "run")
        button_cancel = Button(title = "cancel")
        push!(window.items, button_run, button_cancel)

        didClick(button_run) do event
            $(codegen_call(ctx, cmd))
        end
    end
    push!(ret.args, button_expr)

    push!(ret.args, :(return 0))
    return ret
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

function codegen_input(::PoptartCtx, input::Symbol, arg::Arg)
    label = arg.name
    if arg.type != Any
        label *= "::" * string(arg.type)
    end
    if arg.require
        label *= " *"
    end
    label *= "\n$(arg.doc.first)"
    quote
        $input = InputText(buf="")
        push!(window.items, Label($label))
        push!(window.items, $input)
    end
end

function codegen_input(::PoptartCtx, input::Symbol, opt::Option)
    label = opt.name 
    # Probabaly a bad idea to cat strings
    if opt.arg.type != Any
        label *= "::" * string(opt.arg.type)
    end
    if opt.arg.require
        label *= " *"
    end
    label *= "\n$(opt.doc.first)"
    quote
        $input = InputText(buf="")
        push!(window.items, Label($label))
        push!(window.items, $input)
    end
end

function codegen_input(::PoptartCtx, input::Symbol, flag::Flag)
    label = flag.name * "::Bool"
    label *= "\n$(flag.doc.first)"

    quote
        $input = InputText(buf="false")
        push!(window.items, Label($label))
        push!(window.items, $input)
    end
end
