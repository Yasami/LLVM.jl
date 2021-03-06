using Compat

include(joinpath(@__DIR__, "..", "src", "util", "logging.jl"))

const config_path = joinpath(@__DIR__, "ext.jl")
const previous_config_path = config_path * ".bak"

function write_ext(config)
    open(config_path, "w") do io
        println(io, "# autogenerated file, do not edit")
        for (key,val) in config
            println(io, "const $key = $(repr(val))")
        end
    end
end

function main()
    ispath(config_path) && mv(config_path, previous_config_path; remove_destination=true)
    config = Dict{Symbol,Any}()


    ## discover stuff

    VERSION >= v"0.7.0-DEV.2576" || error("This version of LLVM.jl requires Julia 0.7")

    libllvm_name = if Compat.Sys.isapple()
        "libLLVM.dylib"
    elseif Compat.Sys.iswindows()
        "LLVM.dll"
    else
        "libLLVM.so"
    end

    libllvm_paths = if Compat.Sys.iswindows()
        # TODO: Windows build trees
        [joinpath(dirname(JULIA_HOME), "bin", libllvm_name)]
    else
        [joinpath(dirname(JULIA_HOME), "lib", libllvm_name),            # build trees
         joinpath(dirname(JULIA_HOME), "lib", "julia", libllvm_name)]   # dists
     end

    debug("Looking for $(libllvm_name) in ", join(libllvm_paths, ", "))
    filter!(isfile, libllvm_paths)
    isempty(libllvm_paths) && error("Could not find $(libllvm_name), is Julia built with USE_LLVM_SHLIB=1?")
    config[:libllvm_path] = first(libllvm_paths)

    config[:libllvm_version] = VersionNumber(Base.libllvm_version)
    vercmp_match(a,b)  = a.major==b.major &&  a.minor==b.minor
    vercmp_compat(a,b) = a.major>b.major  || (a.major==b.major && a.minor>=b.minor)

    llvmjl_wrappers = filter(path->isdir(joinpath(@__DIR__, "..", "lib", path)),
                             readdir(joinpath(@__DIR__, "..", "lib")))

    matching_wrappers = filter(wrapper->vercmp_match(config[:libllvm_version],
                                                     VersionNumber(wrapper)),
                               llvmjl_wrappers)
    config[:llvmjl_wrapper] = if !isempty(matching_wrappers)
        @assert length(matching_wrappers) == 1
        matching_wrappers[1]
    else
        compatible_wrappers = filter(wrapper->vercmp_compat(config[:libllvm_version],
                                                            VersionNumber(wrapper)),
                                     llvmjl_wrappers)
        isempty(compatible_wrappers) || error("Could not find any compatible wrapper for LLVM $(config[:libllvm_version])")
        last(compatible_wrappers)
    end

    # TODO: figure out the name of the native target
    config[:libllvm_targets] = [:NVPTX, :AMDGPU]

    # backwards-compatibility
    config[:libllvm_system] = false
    config[:configured] = true


    ## (re)generate ext.jl

    function globals(mod)
        all_names = names(mod, true)
        filter(name-> !any(name .== [module_name(mod), Symbol("#eval"), :eval]), all_names)
    end

    if isfile(previous_config_path)
        @eval module Previous; include($previous_config_path); end
        previous_config = Dict{Symbol,Any}(name => getfield(Previous, name)
                                           for name in globals(Previous))

        if config == previous_config
            info("LLVM.jl has already been built for this toolchain, no need to rebuild")
            mv(previous_config_path, config_path; remove_destination=true)
            return
        end
    end

    write_ext(config)

    return
end

main()
