
"""
    PoptartCtx

Poptart code generation context.
"""
mutable struct PoptartCtx <: AbstractCtx
    ptr::Int
    help::Symbol
    version::Symbol
end

PoptartCtx() = PoptartCtx(1, gensym(:help), gensym(:version))

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
        # let Julia throw InterruptException on SIGINT
        # ccall(:jl_exit_on_sigint, Cvoid, (Cint,), 0)
        # $(codegen_scan_glob(ctx, cmd))
        $(codegen(ctx, cmd))
    end
    return quote
        import Poptart
        using Poptart.Desktop
        window = Window()
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
    parameters = gensym(:parameters)
    n_args = gensym(:n_args)
    nrequires = nrequired_args(cmd.args)
    ret = Expr(:block)
    validate_ex = Expr(:block)

    pushmaybe!(ret, codegen_params(ctx, parameters, cmd))

    # if nrequires > 0
    #     err = xerror(
    #         :("command $($(cmd.name)) expect at least $($nrequires) arguments, got $($n_args)"),
    #     )
    #     push!(validate_ex.args, quote
    #         if $n_args < $nrequires
    #             $err
    #         end
    #     end)
    # end

    # # Error: too much arguments
    # if isempty(cmd.args) || !last(cmd.args).vararg
    #     nmost = length(cmd.args)
    #     err = xerror(:("command $($(cmd.name)) expect at most $($nmost) arguments, got $($n_args)"))
    #     push!(validate_ex.args, quote
    #         if $n_args > $nmost
    #             $err
    #         end
    #     end)
    # end

    # push!(ret.args, :($n_args = length(ARGS) - $(ctx.ptr - 1)))
    # push!(ret.args, validate_ex)
    push!(ret.args, codegen_call(ctx, parameters, n_args, cmd))
    push!(ret.args, :(return 0))
    return ret
end

function codegen_params(ctx::PoptartCtx, params::Symbol, cmd::LeafCommand)
    hasparameters(cmd) || return

    regexes, actions = [], []
    controls = []
    arg = gensym(:arg)
    it = gensym(:index)

    for opt in cmd.options
        push!(regexes, regex_flag(opt))
        push!(regexes, regex_option(opt))

        push!(actions, read_forward(params, it, opt))
        push!(actions, read_match(params, it, opt))

        push!(controls, InputText(label=opt.name, buf=""))

        if opt.short
            push!(regexes, regex_short_flag(opt))
            push!(regexes, regex_short_option(opt))

            push!(actions, read_forward(params, it, opt))
            push!(actions, read_match(params, it, opt))
        end
    end

    for flag in cmd.flags
        push!(regexes, regex_flag(flag))
        push!(actions, read_flag(params, it, flag))

        push!(controls, InputText(label=flag.name, buf=""))

        if flag.short
            push!(regexes, regex_short_flag(flag))
            push!(actions, read_flag(params, it, flag))
        end
    end

    return quote
        append!(window.items, $controls)

        # $params = []
        # $it = $(ctx.ptr)
        # while !isempty(ARGS) && $(ctx.ptr) <= $it <= length(ARGS)
        #     $arg = ARGS[$it]
        #     if startswith($arg, "-") # is a flag/option
        #         $(xmatch(regexes, actions, arg))
        #     else
        #         $it += 1
        #     end
        # end
     
    end
end

function codegen_call(ctx::PoptartCtx, params::Symbol, n_args::Symbol, cmd::LeafCommand)
    ex_call = Expr(:call, cmd.entry)
    if hasparameters(cmd)
        push!(ex_call.args, Expr(:parameters, :($params...)))
    end

    # since we will check the position of arguments
    # the optional and variational arguments are always in the end
    for (i, arg) in enumerate(cmd.args)
        if arg.require
            push!(ex_call.args, xparse_args(arg, ctx.ptr + i - 1))
        else
            break
        end
    end

    all_required(cmd) && return code_gen_button(ex_call)

    # handle optional arguments
    ex = Expr(:block)
    if cmd.nrequire >= 0
        push!(ex.args, Expr(:if, :($n_args == $(cmd.nrequire)), ex_call))
    end

    expanded_call_ex = copy(ex_call)
    for i in cmd.nrequire+1:length(cmd.args)
        expanded_call_ex = copy(expanded_call_ex)
        push!(expanded_call_ex.args, xparse_args(cmd.args[i], ctx.ptr + i - 1))
        push!(ex.args, Expr(:if, :($n_args == $i), expanded_call_ex))
    end

    @info "generate button_run!"
    return code_gen_button(ex)
end

function code_gen_button(ex)
    quote
        button_run = Button(title = "run")
        push!(window.items, button_run)
    
        didClick(button_run) do event
            $ex
        end
    end
end

parse_bool(s::String) = (lowercase(s) in ["yes", "true"]) ? true : false