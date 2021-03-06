"""
    set_cmd!(cmds::Dict, cmd)

register `cmd` in the command registry `cmds`, which usually is
a constant `CASTED_COMMANDS` under given module.
"""
function set_cmd!(cmds::Dict, cmd, name = cmd_name(cmd))
    if haskey(cmds, name)
        @warn "replacing command $name in the registry"
    end

    return cmds[name] = cmd
end

"""
    command(module; name="", doc=docstring(m))

Convert a module to a CLI command [`NodeCommand`](@ref).

    command(f::Function, args, kwargs; name="")

Convert a function to a CLI command [`LeafCommand`](@ref).
It requires a `Vector` of function arguments and
a `Vector` of function kwargs.

The element of arguments vector is a tuple
(name, type, require):

- `name::String` is the name of argument
- `type::DataType` is the type of this argument, can be `Any` if you don't want to specify
- `require::Bool` indicates the whether this argument is required.
- `vararg::Bool` indicates whether this argument is a vararg.

The element of kwargs vector is also a tuple
(name, type, short):

- `name::String` is the name of kwarg
- `type::DataType` is the type of this kwarg, can be `Any` if you don't want to specify
- `short::Bool` is a flag that indicates whether this kwarg has short option.
"""
function command end

function command(m::Module; name = "", doc = docstring(m), line = LineNumberNode(0))
    if isempty(name) # force to have a valid name
        name = default_name(m)
    end
    NodeCommand(name, line, doc, collect(values(m.CASTED_COMMANDS)))
end

function command(f::Function, args, kwargs; name = "", line = LineNumberNode(0))
    if isempty(name) # force to have a valid name
        name = default_name(f)
    end
    md = Base.Docs.doc(f)
    intro, doc_args, flag_docs, option_docs = read_doc(md)
    args = create_args(args, doc_args, line)
    options, flags = create_options_and_flags(kwargs, option_docs, flag_docs, line)
    LeafCommand(
        f;
        name = name,
        args = args,
        options = options,
        flags = flags,
        doc = intro,
        line = line,
    )
end

function create_args(args, docs, line)
    ret = Arg[]
    for (name, type, require, vararg, default) in args
        push!(
            ret,
            Arg(
                name;
                type = type,
                require = require,
                doc = get(docs, name, ""),
                line = line,
                vararg = vararg,
                default = default,
            ),
        )
    end
    return ret
end

function create_options_and_flags(kwargs, option_docs, flag_docs, line)
    flags, options = Flag[], Option[]
    for (name, type, isflag, default) in kwargs
        if isflag
            push!(flags, create_flag(name, type, flag_docs, line))
        else
            push!(options, create_option(name, type, option_docs, line, default))
        end
    end
    return options, flags
end

function create_flag(name::String, type, flag_docs, line)
    name = convert_undercore_to_dash(name)
    if haskey(flag_docs, name)
        doc, short = flag_docs[name]
        return Flag(name, line, doc, short)
    else
        return Flag(name; line = line)
    end
end

function create_option(name::String, type, option_docs, line, default)
    name = convert_undercore_to_dash(name)
    if haskey(option_docs, name)
        arg, doc, short = option_docs[name]
        return Option(
            name,
            Arg(arg; type = type, default = default);
            short = short,
            doc = doc,
            line = line,
        )
    else
        return Option(name, Arg(; type = type, line = line, default = default); line = line)
    end
end

function main(
    m::Module = Main;
    name = default_name(m),
    doc = "",
    version = get_version(m),
    line = LineNumberNode(0),
)
    cmd = NodeCommand(name, line, doc, collect(values(m.CASTED_COMMANDS)))
    return EntryCommand(cmd; version = version, line = line)
end
