BINARY_ID = "RITE"
BINARY_VERSION = "0006"
HEADER_SIZE = 22
COMPILER_NAME = "MATZ"
COMPILER_VERSION = "0000"

IREP_SECTION_ID = "IREP"
IREP_VERSION = "0002"
IREP_HEADER_SIZE = 12
RECORD_LENGTH_BYTES = 4

END_SECTION_ID = "END\0"

class Mruby_bytecode
    def initialize(file_name)
        @file_name = file_name
    end

    def byte2_to_bin(l)
        bin = []
        bin[0] = (l >> 8) & 0xff
        bin[1] = l & 0xff
        return bin
    end

    def byte3_to_bin(l)
        bin = []
        bin[0] = (l >> 16) & 0xff
        bin[1] = (l >> 8) & 0xff
        bin[2] = l & 0xff
        return bin
    end

    def byte4_to_bin(l)
        bin = []
        bin[0] = (l >> 24) & 0xff
        bin[1] = (l >> 16) & 0xff
        bin[2] = (l >> 8) & 0xff
        bin[3] = l & 0xff
        return bin
    end

    def calc_crc_16_ccitt(src,crc)
        crcwk = crc << 8
        src.each do |data|
            crcwk |= data
            for i in 0...8 do
                crcwk <<= 1
                if(crcwk & 0x01000000)!= 0 then
                    crcwk ^= (0x11021 << 8)
                end
            end
        end
        return crcwk >> 8
    end

    def make_binary
        @byte_code = @header + @irep + @end
    end

    def make_header
        binary_id = BINARY_ID.bytes
        binay_version = BINARY_VERSION.bytes
        compiler_name = COMPILER_NAME.bytes
        compiler_version = COMPILER_VERSION.bytes
        binary_size = byte4_to_bin(HEADER_SIZE + @irep.size + @end.size)
        compiler = compiler_name + compiler_version
        crc = calc_crc_16_ccitt((binary_size + compiler + @irep + @end) , 0)
        crc = byte2_to_bin(crc)
        @header = binary_id + binay_version + crc + binary_size + compiler
    end

    def make_literal_table
        @op_array[3] =~ /^;*"*(.*?)"*$/
        if @op_array[0] == "OP_LOADL" then
            n = $1
            if n =~ /^\w+\.\w+$/ then
                @literal_table[@irep_location].push(n.to_f)
            else
                @literal_table[@irep_location].push(n.to_i)
            end
        else
            @literal_table[@irep_location].push($1)
        end
    end

    def make_symbol_table(symbol)
        symbol =~ /^(?:R\d)*:*(\$*\@*\w+)$/
        index = @symbol_table[@irep_location].index($1)
        if index == nil then
            @symbol_table[@irep_location].push($1)
        end
    end

    def make_table
        @irep_name = []
        irep_locaiton_hash = {}
        @label = {}
        @irep_location = -1
        @pc = []
        @literal_table = []
        @symbol_table = []

        File.open(@file_name , "r") do |f|
            f.each_line do |line|
                @op_array = line.split
                if @op_array[0] == "irep" then
                    @irep_location += 1
                    @irep_name << []
                    if @irep_location >= 1 then
                        @irep_name[irep_locaiton_hash[@op_array[1]]].push(@op_array[1])
                    end
                    @literal_table << []
                    @symbol_table << []
                    @pc.push(0)
                    next
                end

                if @op_array[0] =~ /^(\w+):$/
                    @label[$1] = @pc[@irep_location]
                    next 
                end

                if @irep_location == -1 then
                    puts "error: nothing \"irep\" first line "
                    exit
                end

                case @op_array[0]
                when "OP_LOADL" , "OP_STRING" , "OP_JMP" , "OP_ONERR" then
                    @pc[@irep_location] += 3
                when "OP_JMPIF" , "OP_JMPNOT" , "OP_JMPNIL" , "OP_ARGARY" , "OP_ENTER" , "OP_BLKPUSH" then
                    @pc[@irep_location] += 4
                else
                    @pc[@irep_location] += @op_array.size
                end

                if @op_array[0] == "OP_LAMBDA" || @op_array[0] == "OP_BLOCK" || @op_array[0] == "OP_METHOD" || @op_array[0] == "OP_EXEC" then
                    @op_array[2] =~ /^I\((\w+)\)$/
                    irep_locaiton_hash[$1] = @irep_location
                end

                case @op_array[0]
                when "OP_LOADL" , "OP_STRING" , "OP_ERR" then
                    self.make_literal_table
                when "OP_SETGV" , "OP_SETIV" , "OP_SETSV" , "OP_SETCV" , "OP_SETCONST" , "OP_SETMCNST" , "OP_UNDEF" then
                    self.make_symbol_table(@op_array[1])
                when "OP_LOADSYM" , "OP_GETGV" , "OP_GETIV" , "OP_GETSV" , "OP_GETCV" , "OP_GETCONST" , "OP_GETMCNST" ,
                     "OP_SEND" , "OP_SENDB" , "OP_SENDV" , "OP_SENDVB" , "OP_KEY_P" , "OP_KARG" , "OP_DEF" ,
                     "OP_CLASS" , "OP_MODULE" then
                     self.make_symbol_table(@op_array[2])
                when "OP_ALIAS" then
                    self.make_symbol_table(@op_array[1])
                    self.make_symbol_table(@op_array[2])
                end 
            end
        end
    end
    
    def write_z
    end

    def write_b(opr)
        case opr
        when /^-*(\d+)$/ then
            if @ext1 == 1 then
                @iseq.concat(byte2_to_bin($1.to_i))
            else
                @iseq.push($1.to_i)
            end
            
            if @op_array[0] == "OP_SEND" || @op_array[0] == "OP_SENDB" then
                if @nregs < @regs + $1.to_i + 1 then
                    @nregs = @regs + $1.to_i + 1
                end
            elsif @op_array[0] == "OP_SENDV" 
                if @nregs < @regs + 2 then
                    @nregs = @regs + 2
                end
            elsif @op_array[0] == "OP_SENDVB" 
                if @nregs < @regs + 3 then
                    @nregs = @regs + 3
                end 
            end

        when /^R(\d+)$/ then
            if @op_array[0] == "OP_SEND" || @op_array[0] == "OP_SENDB" || @op_array[0] == "OP_SENDV" || @op_array[0] == "OP_SENDVB" then
                @regs = $1.to_i
            end
            if @ext1 == 1 then
                @iseq.concat(byte2_to_bin($1.to_i))
            else
                @iseq.push($1.to_i)
            end
            if @nregs < $1.to_i then
                @nregs = $1.to_i
            end

        when /^L\((\d+)\)$/ then
            if @ext1 == 1 then
                @iseq.concat(byte2_to_bin($1.to_i))
            else
                @iseq.push($1.to_i)
            end

        when /^(?:R\d)*:*(\$*\@*\w+)$/ then
            if @ext1 == 1 then
                @iseq.concat(byte2_to_bin(@symbol_table[@irep_location].index($1)))
            else
                @iseq.push(@symbol_table[@irep_location].index($1))
            end
        when /^I\((\w+)\)/ then
            if @ext1 == 1 then
                @iseq.concat(byte2_to_bin(@irep_name[@irep_location].index($1)))
            else
                @iseq.push(@irep_name[@irep_location].index($1))
            end

        when nil
            puts "error:opr #{@op_array[0]} needs more operands "
            exit
        else 
            puts "error:opr #{@line_num}line"
            exit
        end
        @ext1 = 0
    end

    def write_bb
        self.write_b(@op_array[1])
        if @ext2 == 1 then
            @ext1 = 1
            @ext2 = 0
        end
        self.write_b(@op_array[2])
    end

    def write_bbb
        self.write_b(@op_array[1])
        if @ext2 == 1 then
            @ext1 = 1
            @ext2 = 0
        end
        self.write_b(@op_array[2])
        if @ext3 == 1 then
            @ext1 = 1
            @ext3 = 0
        end
        self.write_b(@op_array[3])
    end

    def write_s(opr)
        arg = 0
        if opr =~ /^(\d):(\d):(\d):(\d):*\(*(\d)\)*$/ || 
            opr =~ /^{(?:req:(\d))*(?:,*rest:(\d))*(?:,*post:(\d))*(?:,*kdict:(\d))*(?:,*local:(\d))*}$/ then
            req = $1.to_i
            rest = $2.to_i
            post = $3.to_i
            kdict = $4.to_i
            local = $5.to_i

            arg |= (req << 11)
            arg |= (rest << 10)
            arg |= (post << 5)
            arg |= (kdict << 4)
            arg |= local
            @iseq.concat(byte2_to_bin(arg))
        elsif opr =~ /^\w+$/ then
            @iseq.concat(byte2_to_bin(@label[opr]))
        else
            puts "error:opr #{@line_num}line"
            exit
        end
    end

    def write_bs
        self.write_b(@op_array[1])
        if @ext2 == 1 then
            @ext1 = 1
            @ext2 = 0
        end
        self.write_s(@op_array[2])
    end

    def write_w(opr)
        arg = 0
        if opr =~ /^(\d):(\d):(\d):(\d):(\d):(\d):(\d)$/ ||
            opr =~ /^{(?:req:(\d))*(?:,*opt:(\d))*(?:,*rest:(\d))*(?:,*post:(\d))*(?:,*key:(\d))*(?:,*kdict:(\d))*(?:,*block:(\d))*}$/ then
            req = $1.to_i
            opt = $2.to_i
            rest= $3.to_i
            post = $4.to_i
            key = $5.to_i
            kdict = $6.to_i
            block = $7.to_i

            arg |= (req << 18)
            arg |= (opt << 13)
            arg |= (rest << 12)
            arg |= (post << 7)
            arg |= (key << 2)
            arg |= (kdict << 1)
            arg |= block
            @iseq.concat(byte3_to_bin(arg))
        else
            puts "error:opr #{@line_num}line"
            exit
        end
    end

    def write_opr(opc,type)
        @iseq.push(opc)
        case type
        when "Z" then
            self.write_z
        when "B" then
            self.write_b(@op_array[1])
        when "BB" then
            self.write_bb
        when "BBB" then
            self.write_bbb
        when "S" then
            self.write_s(@op_array[1])
        when "BS" then
            self.write_bs
        when "W" then
            self.write_w(@op_array[1])
        end 
    end

    def make_iseq
        @iseq = []
        @irep_location = -1
        @nloacals = 0
        @nregs = 0
        @add_regs = 1
        @rlen = 0
        @ilen = 0
        @add_ilen = 0
        @line_num = 0

        File.open(@file_name , "r") do |f|
            f.each_line do |line|
                @op_array = line.split
                @line_num += 1
                case @op_array[0] 
                when "irep" then
                    self.make_record
                    @iseq = []
                    @irep_location += 1 
                    @nloacals = 0
                    @nregs = 0
                    @add_regs = 1
                    @rlen = 0
                    @ilen = 0
                    @add_ilen = 0
                    next

                when /^\w+:$/ then
                    next

                when nil then
                    next
                    
                when "OP_NOP" then
                    self.write_opr(0x00,"Z")

                when "OP_MOVE" then
                    self.write_opr(0x01,"BB")

                when "OP_LOADL" then
                    self.write_opr(0x02,"BB")
                    
                when "OP_LOADI" then
                    self.write_opr(0x03,"BB")

                when "OP_LOADINEG" then
                    self.write_opr(0x04,"BB")

                when "OP_LOADI__1"
                    self.write_opr(0x05,"B")

                when "OP_LOADI_0" then
                    self.write_opr(0x06,"B")

                when "OP_LOADI_1" then
                    self.write_opr(0x07,"B")

                when "OP_LOADI_2" then
                    self.write_opr(0x08,"B")

                when "OP_LOADI_3" then
                    self.write_opr(0x09,"B")

                when "OP_LOADI_4" then
                    self.write_opr(0x0a,"B")

                when "OP_LOADI_5" then
                    self.write_opr(0x0b,"B")

                when "OP_LOADI_6" then
                    self.write_opr(0x0c,"B")

                when "OP_LOADI_7" then
                    self.write_opr(0x0d,"B")

                when "OP_LOADSYM" then
                    self.write_opr(0x0e,"BB")

                when "OP_LOADNIL" then
                    self.write_opr(0x0f,"B")

                when "OP_LOADSELF" then
                    self.write_opr(0x10,"B")

                when "OP_LOADT" then
                    self.write_opr(0x11,"B")

                when "OP_LOADF" then
                    self.write_opr(0x12,"B")
                
                when "OP_GETGV" then
                    self.write_opr(0x13,"BB")
                
                when "OP_SETGV" then  
                    @op_array[1] , @op_array[2] = @op_array[2] , @op_array[1]
                    self.write_opr(0x14,"BB")

                when "OP_GETSV" then
                    self.write_opr(0x15,"BB")

                when "OP_SETSV" then
                    @op_array[1] , @op_array[2] = @op_array[2] , @op_array[1]
                    self.write_opr(0x16,"BB")

                when "OP_GETIV" then
                    self.write_opr(0x17,"BB")
                
                when "OP_SETIV"  then
                    @op_array[1] , @op_array[2] = @op_array[2] , @op_array[1]
                    self.write_opr(0x18,"BB")

                when "OP_GETCV" then
                    self.write_opr(0x19,"BB")

                when "OP_SETCV" then
                    @op_array[1] , @op_array[2] = @op_array[2] , @op_array[1]
                    self.write_opr(0x1a,"BB")

                when "OP_GETCONST" then
                    self.write_opr(0x1b,"BB")
                
                when "OP_SETCONST"  then
                    @op_array[1] , @op_array[2] = @op_array[2] , @op_array[1]
                    self.write_opr(0x1c,"BB")

                when "OP_GETMCNST" then
                    self.write_opr(0x1d,"BB")

                when "OP_SETMCNST" then
                    @op_array[1] , @op_array[2] = @op_array[2] , @op_array[1]
                    self.write_opr(0x1e,"BB")

                when "OP_GETUPVAR" then
                    self.write_opr(0x1f,"BBB")

                when "OP_SETUPVAR" then
                    self.write_opr(0x20,"BBB")

                when "OP_JMP" then
                    self.write_opr(0x21,"S")

                when "OP_JMPIF" then
                    self.write_opr(0x22,"BS")

                when "OP_JMPNOT" then
                    self.write_opr(0x23,"BS")

                when "OP_JMPNIL" then
                    self.write_opr(0x24,"BS")

                when "OP_ONERR" then
                    self.write_opr(0x25,"S")

                when "OP_EXCEPT" then
                    self.write_opr(0x26,"B")

                when "OP_RESCUE" then
                    self.write_opr(0x27,"BB")

                when "OP_POPERR" then
                    self.write_opr(0x28,"B")

                when "OP_RAISE" then
                    self.write_opr(0x29,"B") 

                when "OP_EPUSH" then 
                    @rlen += 1
                    self.write_opr(0x2a,"B") 
                    
                when "OP_EPOP" then
                    self.write_opr(0x2b,"B")

                when "OP_SENDV" then
                    self.write_opr(0x2c,"BB")

                when "OP_SENDVB" then
                    self.write_opr(0x2d,"BB")

                when "OP_SEND" then   
                    self.write_opr(0x2e,"BBB")  

                when "OP_SENDB" then
                    self.write_opr(0x2f,"BBB")

                when "OP_CALL" then
                    self.write_opr(0x30,"Z")

                when "OP_SUPER" then
                    self.write_opr(0x31,"BB")

                when "OP_ARGARY" then
                    self.write_opr(0x32,"BS")
                        
                when "OP_ENTER" then
                    self.write_opr(0x33,"W")

                when "OP_KEY_P" then
                    self.write_opr(0x34,"BB")

                when "OP_KEYEND" then
                    self.write_opr(0x35,"Z")
                
                when "OP_KARG" then
                    self.write_opr(0x36,"BB") 

                when "OP_RETURN" then
                    self.write_opr(0x37,"B")

                when "OP_RETURN_BLK" then
                    self.write_opr(0x38,"B")

                when "OP_BREAK" then
                    self.write_opr(0x39,"B")

                when "OP_BLKPUSH" then
                    self.write_opr(0x3a,"BS")

                when "OP_ADD" then
                    self.write_opr(0x3b,"B")

                when "OP_ADDI" then
                    self.write_opr(0x3c,"BB") 

                when "OP_SUB" then
                    self.write_opr(0x3d,"B")

                when "OP_SUBI" then
                    self.write_opr(0x3e,"BB")

                when "OP_MUL" then
                    self.write_opr(0x3f,"B")

                when "OP_DIV" then
                    self.write_opr(0x40,"B")

                when "OP_EQ" then
                    self.write_opr(0x41,"B")

                when "OP_LT" then
                    self.write_opr(0x42,"B")

                when "OP_LE" then
                    self.write_opr(0x43,"B")

                when "OP_GT" then
                    self.write_opr(0x44,"B")

                when "OP_GE" then
                    self.write_opr(0x45,"B")

                when "OP_ARRAY" then
                    self.write_opr(0x46,"BB")
                    
                when "OP_ARRAY2" then
                    self.write_opr(0x47,"BBB")

                when "OP_ARYCAT" then
                    self.write_opr(0x48,"B")

                when "OP_ARYPUSH" then
                    self.write_opr(0x49,"B")

                when "OP_ARYDUP" then
                    self.write_opr(0x4a,"B")

                when "OP_AREF" then
                    self.write_opr(0x4b,"BBB")

                when "OP_ASET" then
                    self.write_opr(0x4c,"BBB")

                when "OP_APOST" then
                    self.write_opr(0x4d,"BBB")
                    
                when "OP_INTERN" then
                    self.write_opr(0x4e,"B")
    
                when "OP_STRING" then                
                    self.write_opr(0x4f,"BB")

                when "OP_STRCAT" then
                    self.write_opr(0x50,"B")

                when "OP_HASH" then
                    self.write_opr(0x51,"BB")

                when "OP_HASHADD" then
                    self.write_opr(0x52,"BB")
                
                when "OP_HASHCAT" then
                    self.write_opr(0x53,"B")

                when "OP_LAMBDA" then
                    @rlen += 1
                    self.write_opr(0x54,"BB")

                when "OP_BLOCK" then
                    self.write_opr(0x55,"BB")
    
                when "OP_METHOD" then
                    @rlen += 1
                    self.write_opr(0x56,"BB")

                when "OP_RANGE_INC" then
                    self.write_opr(0x57,"B")

                when "OP_RANGE_EXC" then
                    self.write_opr(0x58,"B")

                when "OP_OCLASS" then
                    self.write_opr(0x59,"B")

                when "OP_CLASS" then
                    self.write_opr(0x5a,"BB")

                when "OP_MODULE" then
                    self.write_opr(0x5b,"BB")

                when "OP_EXEC" then
                    @rlen += 1
                    self.write_opr(0x5c,"BB")

                when "OP_DEF" then
                    self.write_opr(0x5d,"BB")

                when "OP_ALIAS" then
                    self.write_opr(0x5e,"BB")

                when "OP_UNDEF" then
                    self.write_opr(0x5f,"B") 

                when "OP_SCLASS" then
                    self.write_opr(0x60,"B")

                when "OP_TCLASS" then
                    self.write_opr(0x61,"B")

                when "OP_DEBUG" then
                    self.write_opr(0x62,"BBB")

                when "OP_ERR" then
                    self.write_opr(0x63,"B")

                when "OP_EXT1" then
                    self.write_opr(0x64,"Z")
                    @ext1 = 1
                    @add_ilen += 1

                when "OP_EXT2" then
                    self.write_opr(0x65,"Z")
                    @ext2 = 1
                    @add_ilen += 1

                when "OP_EXT3" then
                    self.write_opr(0x66,"Z")
                    @ext3 = 1
                    @add_ilen += 2

                when "OP_STOP" then
                    self.write_opr(0x67,"Z")

                when "OP_ABORT" then
                    self.write_opr(0x68,"Z")

                else
                    puts "error:opc #{@line_num}line"
                    exit
                end
                @op_array = Array.new
            end
        end
    end

    def make_literal
        @literal = []
        if @literal_table[@irep_location].empty? == true then
            @literal = byte4_to_bin(0x00)
            return
        end

        @literal = byte4_to_bin(@literal_table[@irep_location].size)

        @literal_table[@irep_location].each do |a| 
            if a.class == String then
                @literal.push(0x00)
            elsif a.class == Integer then
                @literal.push(0x01)
            elsif a.class == Float then
                @literal.push(0x02)
            end
            @literal.concat(byte2_to_bin(a.to_s.size))
            a.to_s.bytes {|x| @literal.push(x)}
        end
    end

    def make_symbol
        @symbol = []
        if @symbol_table[@irep_location].empty? == true  then 
            @symbol_table = byte4_to_bin(0x00)
            return
        end

        @symbol = byte4_to_bin(@symbol_table[@irep_location].size)

        @symbol_table[@irep_location].each do |a|
            @symbol.concat(byte2_to_bin(a.size))
            a.bytes {|x| @symbol.push(x)}
            @symbol.push(0x00)
        end
    end

    def make_record
        if @iseq.empty? == true then
            return
        end
        

        self.make_literal
        self.make_symbol

        @nloacals = byte2_to_bin(@nloacals)
        @nregs = byte2_to_bin(@nregs + @add_regs)
        @rlen = byte2_to_bin(@rlen)
        @ilen = byte4_to_bin(@pc[@irep_location] + @add_ilen) 

        record_length = byte4_to_bin(RECORD_LENGTH_BYTES + (@record + @nloacals + @nregs + @rlen + @ilen + @iseq + @literal + @symbol).size)
        @record.concat(record_length)
        
        a = HEADER_SIZE + IREP_HEADER_SIZE + (@record + @nloacals + @nregs + @rlen + @ilen).size
        @record.concat(@nloacals,@nregs,@rlen,@ilen)
        if a % 4 == 1 then
            @record.push(0x00,0x00,0x00)
        elsif a % 4 == 2 then
            @record.push(0x00,0x00)
        elsif a % 4 == 3 then
            @record.push(0x00)
        end

        @record.concat(@iseq + @literal + @symbol)
    end

    def make_irep
        @record = []
        self.make_iseq
        self.make_record

        irep_section_id = IREP_SECTION_ID.bytes
        irep_section_length = byte4_to_bin(IREP_HEADER_SIZE + @record.size)
        irep_version = IREP_VERSION.bytes
        irep_header = irep_section_id + irep_section_length + irep_version

        @irep = irep_header + @record
    end

    def make_end
        end_section_length_bytes = 4
        end_section_id =  END_SECTION_ID.bytes
        end_section_length = byte4_to_bin(end_section_id.size + end_section_length_bytes)
        @end = end_section_id + end_section_length
    end

    def make_bytecode
        self.make_table
        self.make_irep
        self.make_end
        self.make_header
        self.make_binary
    end

    def out_file
        File.open(@file_name.gsub(/\.\w+$/,".mrb"),"wb") do |fb|
            fb.write(@byte_code.pack("C*"))
        end
    end
end

puts "file_name?"
file = gets.chomp
if /^.+\.rite$/=~ file then
    body = Mruby_bytecode.new(file)
else
    puts "error: extension"
    exit
end

body.make_bytecode
body.out_file