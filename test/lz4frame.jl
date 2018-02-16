@testset "lz4frame" begin
     testIn = "Far out in the uncharted backwaters of the unfashionable end of the west-
 ern  spiral  arm  of  the  Galaxy  lies  a  small  unregarded  yellow  sun."
    test_size = convert(UInt, length(testIn))
    version = LZ4.LZ4F_getVersion()

    @testset "Errors" begin
        no_error = UInt(0)
        @test !LZ4.LZ4F_isError(no_error)
        @test LZ4.LZ4F_getErrorName(no_error) == "Unspecified error code"
        
        ERROR_GENERIC = typemax(UInt)
        @test LZ4.LZ4F_isError(ERROR_GENERIC)
        @test LZ4.LZ4F_getErrorName(ERROR_GENERIC) == "ERROR_GENERIC"
    end

    @testset "keywords" begin
   
        frame = LZ4.LZ4F_frameInfo_t()
        @test frame.blockSizeID == Cuint(default_size)
        @test frame.blockMode == Cuint(block_linked)
        @test frame.contentChecksumFlag == Cuint(0)
        @test frame.frameType == Cuint(normal_frame)
        @test frame.contentSize == Culonglong(0)
        @test frame.dictID == Cuint(0)
        @test frame.blockChecksumFlag == Cuint(0)

        prefs = LZ4.LZ4F_preferences_t(frame)

        @test prefs.frameInfo == frame
        @test prefs.compressionLevel == Cint(0)
        @test prefs.autoFlush == Cuint(0)
        @test prefs.reserved == (Cuint(0), Cuint(0), Cuint(0), Cuint(0))

        frame = LZ4.LZ4F_frameInfo_t(
            blocksizeid = max64KB,
            blockmode = block_independent,
            contentchecksum = true,
            blockchecksum = true,
            frametype = skippable_frame,
            contentsize = 100
            )

        @test frame.blockSizeID == Cuint(4)
        @test frame.blockMode == Cuint(1)
        @test frame.contentChecksumFlag == Cuint(1)
        @test frame.frameType == Cuint(1)
        @test frame.contentSize == Culonglong(100)
        @test frame.blockChecksumFlag == Cuint(1)

        prefs = LZ4.LZ4F_preferences_t(frame, compressionlevel=5, autoflush = true)

        @test prefs.frameInfo == frame
        @test prefs.compressionLevel == Cint(5)
        @test prefs.autoFlush == Cuint(1)
        @test prefs.reserved == (Cuint(0), Cuint(0), Cuint(0), Cuint(0))

    end

    @testset "CompressionCtx" begin
        ctx = Ref{Ptr{LZ4.LZ4F_cctx}}(C_NULL)

        @test_nowarn err = LZ4.LZ4F_createCompressionContext(ctx, version)
        @test err == 0

        @test_nowarn LZ4.check_context_initialized(ctx[])

        err = LZ4.LZ4F_freeCompressionContext(ctx[])
        @test err == 0
        @test !LZ4.LZ4F_isError(err)

        ctx = Ptr{LZ4.LZ4F_cctx}(C_NULL)
        @test_throws ErrorException LZ4.check_context_initialized(ctx)
    end


    @testset "DecompressionCtx" begin
        dctx = Ref{Ptr{LZ4.LZ4F_dctx}}(C_NULL)

        @test_nowarn err = LZ4.LZ4F_createDecompressionContext(dctx, version)
        @test err == 0

        @test_nowarn LZ4.check_context_initialized(dctx[])

        @test_nowarn LZ4.LZ4F_resetDecompressionContext(dctx[])

        err = LZ4.LZ4F_freeDecompressionContext(dctx[])
        @test err == 0

        dctx = Ptr{LZ4.LZ4F_dctx}(C_NULL)
        @test_throws ErrorException LZ4.check_context_initialized(dctx)
        @test_throws ErrorException LZ4.LZ4F_resetDecompressionContext(dctx)

    end

    function test_decompress(origsize, buffer)
        @testset "Decompress" begin
            dctx = Ref{Ptr{LZ4.LZ4F_dctx}}(C_NULL)
            srcsize = Ref{Csize_t}(origsize)
            dstsize =  Ref{Csize_t}(8*1280)
            decbuffer = Vector{UInt8}(1280)

            frameinfo = Ref(LZ4.LZ4F_frameInfo_t())

            @test_nowarn err = LZ4.LZ4F_createDecompressionContext(dctx, version)

            @test_nowarn result = LZ4.LZ4F_getFrameInfo(dctx[], frameinfo, buffer, srcsize)
            @test srcsize[] > 0

            offset = srcsize[]
            srcsize[] = origsize - offset

            @test_nowarn result = LZ4.LZ4F_decompress(dctx[], decbuffer, dstsize, pointer(buffer) + offset, srcsize, C_NULL)
            @test srcsize[] > 0

            @test testIn == unsafe_string(pointer(decbuffer), dstsize[])

            result = LZ4.LZ4F_freeDecompressionContext(dctx[])
            @test !LZ4.LZ4F_isError(result)
        end

    end

    function test_invalid_decompress(origsize, buffer)
        @testset "DecompressInvalid" begin

            dctx = Ref{Ptr{LZ4.LZ4F_dctx}}(C_NULL)
            srcsize = Ref{Csize_t}(origsize)
            dstsize =  Ref{Csize_t}(1280)
            decbuffer = Vector{UInt8}(1280)

            frameinfo = Ref(LZ4.LZ4F_frameInfo_t())

            LZ4.LZ4F_createDecompressionContext(dctx, version)

            buffer[1:LZ4.LZ4F_HEADER_SIZE_MAX] = 0x10
            @test_throws ErrorException LZ4.LZ4F_getFrameInfo(dctx[], frameinfo, buffer, srcsize)

            offset = srcsize[]
            srcsize[] = origsize - offset

            @test_throws ErrorException LZ4.LZ4F_decompress(dctx[], decbuffer, dstsize, pointer(buffer) + offset, srcsize, C_NULL)

            result = LZ4.LZ4F_freeDecompressionContext(dctx[])
            @test !LZ4.LZ4F_isError(result)
        end
    end

    @testset "Compress" begin
        ctx = Ref{Ptr{LZ4.LZ4F_cctx}}(C_NULL)
        err = LZ4.LZ4F_isError(LZ4.LZ4F_createCompressionContext(ctx, version))
        @test !err

        prefs = Ptr{LZ4.LZ4F_preferences_t}(C_NULL)

        bound = LZ4.LZ4F_compressBound(test_size, prefs)
        @test bound > 0

        bufsize = bound + LZ4.LZ4F_HEADER_SIZE_MAX
        buffer = Vector{UInt8}(ceil(Int, bound / 8))

        @test_nowarn result = LZ4.LZ4F_compressBegin(ctx[], buffer, bufsize, prefs)

        offset = result
        @test_nowarn result = LZ4.LZ4F_compressUpdate(ctx[], pointer(buffer) + offset, bufsize - offset, pointer(testIn), test_size, C_NULL)

        offset += result
        @test_nowarn result = LZ4.LZ4F_flush(ctx[], pointer(buffer)+offset, bufsize - offset, C_NULL)

        offset += result
        @test_nowarn result = LZ4.LZ4F_compressEnd(ctx[], pointer(buffer)+offset, bufsize - offset, C_NULL)
        @test result > 0

        offset += result

        result = LZ4.LZ4F_freeCompressionContext(ctx[])
        @test !LZ4.LZ4F_isError(result)

        test_decompress(offset, buffer)
        test_invalid_decompress(offset, buffer)
    end

    @testset "CompressUninitialized" begin
        ctx = Ref{Ptr{LZ4.LZ4F_cctx}}(C_NULL)

        prefs = Ptr{LZ4.LZ4F_preferences_t}(C_NULL)

        bufsize = test_size
        buffer = Vector{UInt8}(test_size)

        @test_throws ErrorException LZ4.LZ4F_compressBegin(ctx[], buffer, bufsize, prefs)
        @test_throws ErrorException LZ4.LZ4F_compressUpdate(ctx[], pointer(buffer), bufsize, pointer(testIn), test_size, C_NULL)
        @test_throws ErrorException LZ4.LZ4F_flush(ctx[], pointer(buffer), bufsize, C_NULL)
        @test_throws ErrorException LZ4.LZ4F_compressEnd(ctx[], pointer(buffer), bufsize, C_NULL)
    end

    @testset "CompressInvalid" begin
        ctx = Ref{Ptr{LZ4.LZ4F_cctx}}(C_NULL)
        LZ4.LZ4F_createCompressionContext(ctx, version)

        prefs = Ptr{LZ4.LZ4F_preferences_t}(C_NULL)

        bound = LZ4.LZ4F_compressBound(test_size, prefs)
        @test bound > 0

        bufsize = bound + LZ4.LZ4F_HEADER_SIZE_MAX
        buffer = Vector{UInt8}(ceil(Int, bound / 8))

        @test_throws ErrorException LZ4.LZ4F_compressBegin(ctx[], buffer, UInt(2), prefs)
        @test_throws ErrorException LZ4.LZ4F_compressUpdate(ctx[], pointer(buffer), bufsize, pointer(testIn), test_size, C_NULL)

        result = LZ4.LZ4F_freeCompressionContext(ctx[])
        @test !LZ4.LZ4F_isError(result)


        ctx = Ref{Ptr{LZ4.LZ4F_cctx}}(C_NULL)
        LZ4.LZ4F_createCompressionContext(ctx, version)

        @test_nowarn result = LZ4.LZ4F_compressBegin(ctx[], buffer, bufsize, prefs)

        offset = result
        @test_nowarn result = LZ4.LZ4F_compressUpdate(ctx[], pointer(buffer) + offset, bufsize - offset, pointer(testIn), test_size, C_NULL)

        @test_throws ErrorException LZ4.LZ4F_flush(ctx[], pointer(buffer), UInt(2), C_NULL)
        @test_throws ErrorException LZ4.LZ4F_compressEnd(ctx[], pointer(buffer), UInt(2), C_NULL)

        result = LZ4.LZ4F_freeCompressionContext(ctx[])
        @test !LZ4.LZ4F_isError(result)
    end

    @testset "DecompressUninitialized" begin
        dctx = Ref{Ptr{LZ4.LZ4F_dctx}}(C_NULL)
        srcsize = Ref{Csize_t}(test_size)
        dstsize =  Ref{Csize_t}(8*1280)
        decbuffer = Vector{UInt8}(1280)

        frameinfo = Ref(LZ4.LZ4F_frameInfo_t())
        @test_throws ErrorException LZ4.LZ4F_getFrameInfo(dctx[], frameinfo, pointer(testIn), srcsize)
        @test_throws ErrorException LZ4.LZ4F_decompress(dctx[], decbuffer, dstsize, pointer(testIn), srcsize, C_NULL)
    end

    @testset "Preferences" begin
        ctx = Ref{Ptr{LZ4.LZ4F_cctx}}(C_NULL)
        err = LZ4.LZ4F_isError(LZ4.LZ4F_createCompressionContext(ctx, version))
        @test !err
        opts = Ref(LZ4.LZ4F_compressOptions_t(1, (0, 0, 0)))
        prefs = Ref(LZ4.LZ4F_preferences_t(LZ4.LZ4F_frameInfo_t(), 20, 0, (0, 0, 0, 0)))

        bound = LZ4.LZ4F_compressBound(test_size, prefs)
        @test bound > 0

        bufsize = bound + LZ4.LZ4F_HEADER_SIZE_MAX
        buffer = Vector{UInt8}(ceil(Int, bound / 8))

        @test_nowarn result = LZ4.LZ4F_compressBegin(ctx[], buffer, bufsize, prefs)

        offset = result
        @test_nowarn result = LZ4.LZ4F_compressUpdate(ctx[], pointer(buffer) + offset, bufsize - offset, pointer(testIn), test_size, opts)

        offset += result
        @test_nowarn result = LZ4.LZ4F_flush(ctx[], pointer(buffer) + offset, bufsize - offset, opts)

        offset += result
        @test_nowarn result = LZ4.LZ4F_compressEnd(ctx[], pointer(buffer) + offset, bufsize - offset, opts)
        @test result > 0

        offset += result

        result = LZ4.LZ4F_freeCompressionContext(ctx[])
        @test !LZ4.LZ4F_isError(result)

        test_decompress(offset, buffer)
    end

end


