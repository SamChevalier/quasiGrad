using Pkg
Pkg.activate(DEPOT_PATH[1])

# if we're using the sysimage, call QuasiGrad directly
using QuasiGrad

# otherwise, include it directy!
# => include("./src/QuasiGrad.jl")

function MyJulia1(InFile1::String, TimeLimitInSeconds::Int64, Division::Int64, NetworkModel::String, AllowSwitching::Int64; run::Bool=true)
    println("running MyJulia1")
    println("  $(InFile1)")
    println("  $(TimeLimitInSeconds)")
    println("  $(Division)")
    println("  $(NetworkModel)")
    println("  $(AllowSwitching)")

    # warmup
    # => NewTimeLimitInSeconds = 1500.0
    # => pc(InFile1, NewTimeLimitInSeconds, Division, NetworkModel, AllowSwitching)

    # begin
    t0 = time()

    # how long did package loading take? Give it 15.0 sec
    NewTimeLimitInSeconds = Float64(TimeLimitInSeconds) - 15.0

    # run!
    if run == true
        # in this case, solve the system -- which division are we solving?
        if Division == 1
            QuasiGrad.compute_quasiGrad_solution_d1(InFile1, NewTimeLimitInSeconds, Division, NetworkModel, AllowSwitching; post_process=false)
        elseif (Division == 2) || (Division == 3)
            QuasiGrad.compute_quasiGrad_solution_d23(InFile1, NewTimeLimitInSeconds, Division, NetworkModel, AllowSwitching; post_process=false)
        else
            println("Division not recognized!")
        end
    else
        # this is just a precompilation trick
        QuasiGrad.compute_quasiGrad_solution_d1(InFile1, NewTimeLimitInSeconds, Division, NetworkModel, AllowSwitching; post_process=true, run=false)
        QuasiGrad.compute_quasiGrad_solution_d23(InFile1, NewTimeLimitInSeconds, Division, NetworkModel, AllowSwitching; post_process=true, run=false)
    end

    # how long did that take?
    tf = time() - t0
    println("final time: $tf")
end

function pc(InFile1::String, NewTimeLimitInSeconds::Float64, Division::Int64, NetworkModel::String, AllowSwitching::Int64)
    jsn = QuasiGrad.load_json(InFile1)
    adm, cgd, ctg, flw, grd, idx, lbf, mgd, ntk, prm, qG, scr, stt, sys, upd = 
        QuasiGrad.base_initialization(jsn, Div=1, hpc_params=true);

    # call this, but don't actually run it
    TimeLimitInSeconds = 600
    MyJulia1(InFile1, TimeLimitInSeconds, Division, NetworkModel, AllowSwitching; run=false)

    # assign a short run-time
    qG.adam_max_time = 3.0

    # in this case, run a minisolve with the 14 bus system
    QuasiGrad.economic_dispatch_initialization!(cgd, ctg, flw, grd, idx, mgd, ntk, prm, qG, scr, stt, sys, upd)
    QuasiGrad.solve_power_flow!(adm, cgd, ctg, flw, grd, idx, lbf, mgd, ntk, prm, qG, scr, stt, sys, upd; first_solve=true)
    QuasiGrad.solve_power_flow_23k!(adm, cgd, ctg, flw, grd, idx, lbf, mgd, ntk, prm, qG, scr, stt, sys, upd; first_solve=true, last_solve=false)
    QuasiGrad.initialize_ctg_lists!(cgd, ctg, flw, grd, idx, mgd, ntk, prm, qG, scr, stt, sys)
    QuasiGrad.soft_reserve_cleanup!(idx, prm, qG, stt, sys, upd)
    QuasiGrad.run_adam!(adm, cgd, ctg, flw, grd, idx, mgd, ntk, prm, qG, scr, stt, sys, upd)
    QuasiGrad.project!(100.0, idx, prm, qG, stt, sys, upd, final_projection = false)
    QuasiGrad.snap_shunts!(true, prm, qG, stt, upd)
    QuasiGrad.count_active_binaries!(prm, upd)
    QuasiGrad.solve_power_flow!(adm, cgd, ctg, flw, grd, idx, lbf, mgd, ntk, prm, qG, scr, stt, sys, upd; last_solve=true)
    QuasiGrad.soft_reserve_cleanup!(idx, prm, qG, stt, sys, upd)
    QuasiGrad.run_adam!(adm, cgd, ctg, flw, grd, idx, mgd, ntk, prm, qG, scr, stt, sys, upd)
    QuasiGrad.project!(100.0, idx, prm, qG, stt, sys, upd, final_projection = true)
    QuasiGrad.cleanup_constrained_pf_with_Gurobi_parallelized!(cgd, ctg, flw, grd, idx, mgd, ntk, prm, qG, scr, stt, sys, upd)
    QuasiGrad.reserve_cleanup!(idx, prm, qG, stt, sys, upd)

    qG.write_location = "local"
    QuasiGrad.write_solution("./src/junk.json", prm, qG, stt, sys)
    QuasiGrad.post_process_stats(true, cgd, ctg, flw, grd, idx, mgd, ntk, prm, qG, scr, stt, sys)
end