BINARY_ID = "RITE"
BINARY_VERSION = "0006"
HEADER_SIZE = 22
COMPILER_NAME = "MATZ"
COMPILER_VERSION = "0000"

IREP_SECTION_ID = "IREP"
IREP_VERSION = "0002"
IREP_HEADER_SIZE = 12

END_SECTION_ID = "END\0"

class Binary
    def initialize(file_name) 
       @file_name = file_name
    end

    def bin_to_2bytes(l)
        bin = []
        bin[0] = (l >> 8) & 0xff
        bin[1] = l & 0xff
        return bin
    end

    def bin_to_3bytes(l)
        bin = []
        bin[0] = (l >> 16) & 0xff
        bin[1] = (l >> 8) & 0xff
        bin[2] = l & 0xff
        return bin
    end

    def bin_to_4bytes(l)
        bin = []
        bin[0] = (l >> 24) & 0xff
        bin[1] = (l >> 16) & 0xff
        bin[2] = (l >> 8) & 0xff
        bin[3] = l & 0xff
        return bin
    end

    def calc_crc_16_ccitt(src,crc)
        crcwk = crc << 8
        #src_ary = src.to_a
        src.each do |data|
            crcwk |= data
            for i in 0...8 do
                crcwk <<= 1
                if(crcwk & 0x01000000)!= 0 then
                    crcwk ^= (0x11021 << 8)
                end
                #crcwk = crcwk & 0xffffffff
            end
        end
        return crcwk >> 8
    end

    def make_binary
        @binary = @header + @irep + @end
    end
    def make_header
        binary_id = BINARY_ID.bytes
        binay_version = BINARY_VERSION.bytes
        compiler_name = COMPILER_NAME.bytes
        compiler_version = COMPILER_VERSION.bytes
        binary_size = bin_to_4bytes(HEADER_SIZE + @irep.size + @end.size)
        compiler = compiler_name + compiler_version
        crc = calc_crc_16_ccitt((binary_size + compiler + @irep + @end),0)
        crc = bin_to_2bytes(crc)
        @header = binary_id + binay_version + crc + binary_size + compiler
    end

    def make_symbol_table(symbol)
        symbol =~ /^:(\$*\w+)$/
        if @symbol_table == nil then
            @symbol_table.push($~[1])
        elsif
            for i in 0...@symbol_table.size do
                if @symbol_table[i] == $~[1] then
                    return
                end
            end
            @symbol_table.push($~[1])
        end
    end

    def make_literal_table(literal)
        literal =~ /^;"*(.+[^"])"*$/
        @literal_table.push($~[1])
    end

    def make_table
        @irep_name = []
        @label = {}
        @irep_location = -1
        pc = 0
        File.open(@file_name,"r") do |f|
            f.each_line do |line|
                op_array = line.split
                if line.chomp == "" then
                    next
                end

                if op_array[0] =~ /^irep$/ then
                    @irep_location += 1
                    if op_array[1] == nil then
                        @irep_name.push(@irep_location-1)
                    else
                        @irep_name.push(op_array[1])
                    end
                    next
                end

                if op_array[0] =~ /^(\w+):*$/
                    @label[$~[1]] = pc 
                end
                pc += op_array.size
                if op_array[0] == "OP_LOADL" then
                    pc -= 1
                end
            end
        end
    end 

    def fetch_operand(operand)
        if operand =~ /^-*(\d+)$/ then
            @iseq.push($~[1].to_i)
        elsif operand =~ /^R(\d+)$/ then
            @iseq.push($~[1].to_i)
            if @nregs < $~[1].to_i then
                @nregs = $~[1].to_i
            end
        elsif operand =~ /^L\((\d+)\)$/ then
            make_literal_table(@op_array[3])
            @iseq.push($~[1].to_i)
        elsif operand =~ /^:(\$*\w+)$/ then
            make_symbol_table(operand)
            for i in 0...@symbol_table.size do
                if @symbol_table[i] == $~[1] then
                    @iseq.push(i)
                end
            end
        elsif operand =~ /^I\((\w+)\)/ then
            for i in @irep_location...@irep_name.size do
                if @irep_name[i] == $~[1] then
                    @iseq.push(i - (@irep_location + 1))
                end
            end
        end
    end

    def fetch_z(op_code)
        @iseq.push(op_code)
        @pc += 1
        @ilen += 1
    end

    def fetch_b(op_code)
        @iseq.push(op_code)
        self.fetch_operand(@op_array[1])
        @pc += 2
        @ilen += 2
    end

    def fetch_bb(op_code)
        @iseq.push(op_code)
        self.fetch_operand(@op_array[1])
        self.fetch_operand(@op_array[2])
        @pc += 3
        @ilen += 3
    end

    def fetch_bbb(op_code)
        @iseq.push(op_code)
        self.fetch_operand(@op_array[1])
        self.fetch_operand(@op_array[2])
        self.fetch_operand(@op_array[3])
        @pc += 4
        @ilen += 4
    end

    def fetch_s(op_code)
        @iseq.push(op_code)
        @iseq.push(bin_to_2bytes(@label[@op_array[1]])).flatten!
        @pc += 3
        @ilen += 3
    end

    def fetch_bs(op_code)
        @iseq.push(op_code)
        self.fetch_operand(@op_array[1])
        @iseq.push(bin_to_2bytes(@label[@op_array[2]])).flatten!
        @pc += 4
        @ilen += 4
    end

    def fetch_w(op_code)
        @iseq.push(op_code)
        arg = 0

        if @op_array[1] =~ /^(\d):(\d):(\d):(\d):(\d):(\d):(\d)$/ then
            req = $~[1].to_i
            opt = $~[2].to_i
            rest= $~[3].to_i
            post = $~[4].to_i
            key = $~[5].to_i
            kdict = $~[6].to_i
            block = $~[7].to_i
        elsif @op_array[1] =~ /^{(?:req:(\d))*(?:,*opt:(\d))*(?:,*rest:(\d))*(?:,*post:(\d))*(?:,*key:(\d))*(?:,*kdict:(\d))*(?:,*block:(\d))*}$/ then
            req = $~[1].to_i
            opt = $~[2].to_i
            rest= $~[3].to_i
            post = $~[4].to_i
            key = $~[5].to_i
            kdict = $~[6].to_i
            block = $~[7].to_i
        end

        arg |= (req << 18)
        arg |= (opt << 13)
        arg |= (rest << 12)
        arg |= (post << 7)
        arg |= (key << 2)
        arg |= (kdict << 1)
        arg |= block
        @iseq.concat(bin_to_3bytes(arg))
        @pc += 4
        @ilen += 4
    end

    def make_iseq_block
        @pc = 0
        @iseq = []
        @irep_location = -1
        @nloacals = 0
        @nregs = 0
        @add_regs = 1
        @rlen = 0
        @ilen = 0
        @symbol_table = []
        @literal_table = []

        File.open(@file_name,"r") do |f|
            f.each_line do |line|
                @op_array = line.split(" ")
                if @op_array[0] == "irep" then
                    self.make_record
                    @pc = 0
                    @iseq = []
                    @irep_location += 1
                    @nloacals = 0
                    @nregs = 0
                    @add_regs = 1
                    @rlen = 0
                    @ilen = 0
                    @symbol_table = []
                    @literal_table = []
                    next
                end
                
                case @op_array[0]
                when "OP_NOP" then
                    self.fetch_z(0x00)

                when "OP_MOVE" then
                    self.fetch_bb(0x01)

                when "OP_LOADL" then
                    self.fetch_bb(0x02)
                    
                when "OP_LOADI" then
                    self.fetch_bb(0x03)

                when "OP_LOADINEG" then
                    self.fetch_bb(0x04)

                when "OP_LOADI__1"
                    self.fetch_b(0x05)

                when "OP_LOADI_0" then
                    self.fetch_b(0x06)

                when "OP_LOADI_1" then
                    self.fetch_b(0x07)

                when "OP_LOADI_2" then
                    self.fetch_b(0x08)

                when "OP_LOADI_3" then
                    self.fetch_b(0x09)

                when "OP_LOADI_4" then
                    self.fetch_b(0x0a)

                when "OP_LOADI_5" then
                    self.fetch_b(0x0b)

                when "OP_LOADI_6" then
                    self.fetch_b(0x0c)

                when "OP_LOADI_7" then
                    self.fetch_b(0x0d)

                when "OP_LOADSYM" then
                    self.fetch_bb(0x0e)

                when "OP_LOADNIL" then
                    self.fetch_b(0x0f)

                when "OP_LOADSELF" then
                    self.fetch_b(0x10)

                when "OP_LOADT" then
                    self.fetch_b(0x11)

                when "OP_LOADF" then
                    self.fetch_b(0x12)
                
                when "OP_GETGV" then
                    self.fetch_bb(0x13)
                
                when "OP_SETGV" then  
                    @op_array[1] , @op_array[2] = @op_array[2] , @op_array[1]
                    self.fetch_bb(0x14)

                when "OP_GETIV" then
                    self.fetch_bb(0x17)
                
                when "OP_SETIV"  then
                    @op_array[1] , @op_array[2] = @op_array[2] , @op_array[1]
                    self.fetch_bb(0x18)

                when "OP_GETCONST" then
                    self.fetch_bb(0x1b)
                
                when "OP_SETCONST"  then
                    @op_array[1] , @op_array[2] = @op_array[2] , @op_array[1]
                    self.fetch_bb(0x1c)

                when "OP_GETUPVAR" then
                    self.fetch_bbb(0x1f)

                when "OP_SETUPVAR" then
                    self.fetch_bbb(0x20)

                when "OP_JMP" then
                    self.fetch_s(0x21)

                when "OP_JMPIF" then
                    self.fetch_bs(0x22)

                when "OP_JMPNOT" then
                    self.fetch_bs(0x23)

                when "OP_JMPNIL" then
                    self.fetch_bs(0x24)

                when "OP_SENDV" then
                    self.fetch_bb(0x2c)
                    @add_regs += 1

                when "OP_SEND" then   
                    self.fetch_bbb(0x2e)
                    @add_regs += 1

                when "OP_SENDB" then
                    self.fetch_bbb(0x2f)
                    @add_regs += 1
                    
                when "OP_ENTER" then
                    self.fetch_w(0x33)

                when "OP_RETURN" then
                    self.fetch_b(0x37)

                when "OP_RETURN_BLK" then
                    self.fetch_b(0x38)

                when "OP_BREAK" then
                    self.fetch_b(0x39)

                when "OP_ADD" then
                    self.fetch_b(0x3b)

                when "OP_ADDI" then
                    self.fetch_bb(0x3c) 

                when "OP_SUB" then
                    self.fetch_b(0x3d)

                when "OP_SUBI" then
                    self.fetch_bb(0x3e)

                when "OP_MUL" then
                    self.fetch_b(0x3f)

                when "OP_DIV" then
                    self.fetch_b(0x40)

                when "OP_EQ" then
                    self.fetch_b(0x41)

                when "OP_LT" then
                    self.fetch_b(0x42)

                when "OP_LE" then
                    self.fetch_b(0x43)

                when "OP_GT" then
                    self.fetch_b(0x44)

                when "OP_GE" then
                    self.fetch_b(0x45)

                when "OP_ARRAY" then
                    self.fetch_bb(0x46)
                    
                when "OP_ARRAY2" then
                    self.fetch_bbb(0x47)

                when "OP_ARYCAT" then
                    self.fetch_b(0x48)

                when "OP_ARYDUP" then
                    self.fetch_b(0x4a)

                when "OP_AREF" then
                    self.fetch_bbb(0x4b)

                when "OP_APOST" then
                    self.fetch_bbb(0x4d)
                    
                when "OP_INTERN" then
                    self.fetch_b(0x4e)
 
                when "OP_STRING" then                
                    self.fetch_bb(0x4f)

                when "OP_STRCAT" then
                    self.fetch_b(0x50)

                when "OP_HASH" then
                    self.fetch_bb(0x51)
 
                when "OP_METHOD" then
                    @rlen += 1
                    self.fetch_bb(0x56)

                when "OP_DEF" then
                    self.fetch_bb(0x5d)

                when "OP_TCLASS" then
                    self.fetch_b(0x61)

                when "OP_STOP" then
                    self.fetch_z(0x67)
                end
            end
        end
    end

    def make_literal
        @literal = []
        if @literal_table.empty? == true then
            @literal = bin_to_4bytes(0x00)
            return
        end

        @literal = (bin_to_4bytes(@literal_table.size))

        for i in 0...@literal_table.size do
            if @literal_table[i].class == String then
                @literal.push(0x00)
            elsif @literal_table[i] == Float then
                @literal.push(0x02)
            else
                @literal.push(0x01)
            end
            @literal.push(bin_to_2bytes(@literal_table[i].size))
            @literal_table[i].to_s.bytes {|x| @literal.push(x)}
        end
    end
    
    def make_symbol
        @symbol = []
        if @symbol_table.empty? == true then
            @symbol = bin_to_4bytes(0x00)
            return          
        end

        @symbol = (bin_to_4bytes(@symbol_table.size))

        for i in 0...@symbol_table.size do 
            @symbol.concat(bin_to_2bytes(@symbol_table[i].size))
            @symbol_table[i].to_s.bytes {|x| @symbol.push(x)}
            @symbol.push(0x00)
        end
    end

    def make_record
        if @iseq.empty? == true then
            return 
        end
        self.make_literal
        self.make_symbol

        records =[]
        record_length_bytes = 4

        @nloacals = bin_to_2bytes(@nloacals)
        @nregs = bin_to_2bytes(@nregs+@add_regs)
        @rlen = bin_to_2bytes(@rlen)
        @ilen = bin_to_4bytes(@ilen)
        
        record_length = bin_to_4bytes(record_length_bytes + (@nloacals + @nregs + @rlen + @ilen + @iseq + @literal + @symbol).size)

        @record.push(record_length).flatten!
        a = HEADER_SIZE + IREP_HEADER_SIZE + (@record + @nloacals + @nregs + @rlen + @ilen).size
        @record.push(@nloacals,@nregs,@rlen,@ilen)
        if a % 4 == 1 then
            @record.push(0x00,0x00,0x00)
        elsif a % 4 == 2 then
            @record.push(0x00,0x00)
        elsif a % 4 == 3 then
            @record.push(0x00)
        end
        @record.push(@iseq,@literal,@symbol).flatten!

    end

    def make_irep
        @record = []
        self.make_iseq_block
        self.make_record

        irep_section_id = IREP_SECTION_ID.bytes
        irep_section_length = bin_to_4bytes(IREP_HEADER_SIZE + @record.size)
        irep_version = IREP_VERSION.bytes
        irep_header = irep_section_id + irep_section_length + irep_version

        @irep = irep_header + @record
    end

    def make_end
        end_section_length_bytes = 4
        end_section_id =  END_SECTION_ID.bytes
        end_section_length = bin_to_4bytes(end_section_id.size + end_section_length_bytes)
        @end = end_section_id + end_section_length
    end

    def make_bin
        self.make_table
        self.make_irep
        self.make_end
        self.make_header
        self.make_binary
    end

    def out_file
        File.open(@file_name.gsub(/\.\w+$/,".mrb"),"wb") do |fb|
            fb.write(@binary.pack("C*"))
        end
    end
end

puts "file_name?"
file = gets.chomp

body = Binary.new(file)
body.make_bin
body.out_file

