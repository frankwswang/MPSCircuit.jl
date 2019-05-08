#=
Circuit builders for MPSCircuit.jl.
=#
export DCbuilder, MPSbuilder


"""
    DCbuilder(nBit::Int64, depth::Int64)
Structure of elements may needed for a Differentiable circuit.
\nFields:
\n`block::ChainBlock`:   The block for 1 depth.
\n`Cblocks::ChainBlock`: The Blocks chained except head and tail.
\n`body::ChainBlock`:   The Differentiable circuit for n depths. 
\n`head::ChainBlock`:   The "head" of the Differentiable circuit(if directly input bits).
\n`tail::ChainBlock`:    The "tail" of the Differentiable circuit(2 layers of rotaional gates). 
"""
struct DCbuilder
    block::ChainBlock   # The block for 1 depth.
    Cblocks::ChainBlock # The Blocks chained except head and tail.
    body::ChainBlock    # The Differentiable circuit for n depths. 
    head::ChainBlock    # The "head" of the Differentiable circuit(if directly input bits).
    tail::ChainBlock    # The "tail" of the Differentiable circuit(2 layers of rotaional gates).

    function DCbuilder(nBit::Int64, depth::Int64) #DON'T USE repeat to avoid POINTER side-effect!
        block = chain(nBit, vcat([chain(nBit,[put(nBit, i=>Rz(0)) for i=nBit:-1:1])], 
                                 [chain(nBit,[put(nBit, i=>Rx(0)) for i=nBit:-1:1])], 
                                 [chain(nBit,[put(nBit, i=>Rz(0)) for i=nBit:-1:1])], 
                                 [chain(nBit, vcat([control(nBit, i, (i-1)=>X) for i=nBit:-1:2], 
                                                   [control(nBit, 1, nBit=>X)]))] ))
        tail = chain(nBit, vcat([chain(nBit,[put(nBit, i=>Rz(0)) for i=nBit:-1:1])], 
                                [chain(nBit,[put(nBit, i=>Rx(0)) for i=nBit:-1:1])]))
        head = deepcopy(block[2:end])
        blocks = ChainBlock[]
        for i=1:depth push!(blocks, deepcopy(block)) end
        Cblocks = chain(nBit, blocks)
        body = chain(nBit, vcat([head], blocks, [tail])) 
        new(block, Cblocks, body, head, tail)
    end
end


"""
    MPSbuilder(nBitA::Int64, vBit::Int64, rBit::Int64, blockT::Tuple{String, Int64}) -> (circuit::ChainBlock, cExtend::ChainBlock)
    MPSbuilder(nBitA::Int64, vBit::Int64, rBit::Int64, blockT::String) -> (circuit::ChainBlock, cExtend::ChainBlock)
Function for creating different types of MPS circuits. 
\n1st-line method corresponds to blockT = ("DC", depth). "DC" stands for "Differentiable circuit".
\n2nd-line method corresponds to blockT = "CS". "CS" stands for "cluster state".
"""
function MPSbuilder(nBitA::Int64, vBit::Int64, rBit::Int64, blockT::Tuple{String, Int64}) 
    par2nd = setMPSpar(nBitA, vBit, rBit)
    nBlock = par2nd.nBlock
    nBit = par2nd.nBit

    if blockT[1] == "DC" # Differentiable circuit.
        depth = blockT[2]
        swapV1 = chain(nBit, [put(nBit, (inBit,inBit+1)=>SWAP) for irBit=rBit:-1:1 for inBit=irBit  :(vBit+irBit-1)])
        swap1V = chain(nBit, [put(nBit, (inBit+1,inBit)=>SWAP) for irBit=1:   rBit for inBit=(vBit+irBit-1):-1:irBit])
        cBlockHead = chain(nBit, DCbuilder(nBit, depth).block, swapV1) |> markDiff
        cBlocks = [cBlockHead]
        cEBlocks = [put(nBitA, Tuple((nBitA-rBit-vBit+1):nBitA,)=>cBlockHead)]         
        for i=2:nBlock
            cBlockHead = chain(nBit, DCbuilder(nBit, depth).block, swapV1) |> markDiff 
            cBlock =  chain(nBit, vcat([swap1V], cBlockHead.blocks))
            push!(cBlocks, cBlock)
            push!(cEBlocks, put(nBitA, Tuple((nBitA-i*rBit-vBit+1):(nBitA-(i-1)*rBit),)=>cBlockHead))
        end
        circuit = chain(nBit, cBlocks)
        cExtend = chain(nBitA, cEBlocks)
    end

    (circuit, cExtend)
end

function MPSbuilder(nBitA::Int64, vBit::Int64, rBit::Int64, blockT::String)
    par2nd = setMPSpar(nBitA, vBit, rBit)
    nBlock = par2nd.nBlock
    nBit = par2nd.nBit

    if blockT == "CS" # MPS blocks for 1D cluster state.
        if vBit !=1 || rBit !=1
            println("Error: The nBit=vBit+rBit of cluster state MPS blocks should be 2!\n")
            return 0
        end
        cBlocks = ChainBlock[]
        push!(cBlocks, chain(nBit, repeat(nBit,H,(2,1)), control(nBit, 1, nBit=>Z)))
        for i =2:nBlock
            push!(cBlocks, chain(nBit,put(nBit, (2,1)=>SWAP), put(nBit, 1=>H), control(nBit, 1, nBit=>Z)))
        end
        circuit = chain(nBit,cBlocks)  
        cExtend = chain(nBitA, vcat([repeat(nBitA,H,Tuple(nBitA:-1:1,))], [control(nBitA, i-1, i=>Z) for i=nBitA:-1:2])) 
    end
    
    (circuit, cExtend)
end