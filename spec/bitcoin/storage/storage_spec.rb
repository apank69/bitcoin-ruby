# encoding: ascii-8bit

require_relative '../spec_helper'

include Bitcoin
include Bitcoin::Storage
include Bitcoin::Storage::Backends
include Bitcoin::Builder
include Bitcoin::Validation

[ { :name => :dummy },
  { :name => :utxo, :db => 'sqlite:/', :index_all_addrs => true },
  { :name => :sequel, :db => 'sqlite:/' } ].each do |configuration|

  describe "Bitcoin::Storage::Backends::#{configuration[:name].capitalize}Store" do

    before do
      class Bitcoin::Validation::Block; def difficulty; true; end; end
      Bitcoin.network[:proof_of_work_limit] = Bitcoin.encode_compact_bits("ff"*32)

      Bitcoin::network = :testnet
      @store = Bitcoin::Storage.send(configuration[:name], configuration)
      def @store.in_sync?; true; end
      @store.reset
      @store.log.level = 4

      @store.store_block(P::Block.new(fixtures_file('testnet/block_0.bin')))
      @store.store_block(P::Block.new(fixtures_file('testnet/block_1.bin')))
      @store.store_block(P::Block.new(fixtures_file('testnet/block_2.bin')))
      @store.store_block(P::Block.new(fixtures_file('testnet/block_3.bin')))

      unless @store.class.name =~ /UtxoStore/
        @store.store_tx(P::Tx.new(fixtures_file('rawtx-01.bin')), false)
        @store.store_tx(P::Tx.new(fixtures_file('rawtx-02.bin')), false)
      end

      @blk = P::Block.new(fixtures_file('testnet/block_4.bin'))
      @tx = P::Tx.new(fixtures_file('rawtx-03.bin'))
    end

    after do
      class Bitcoin::Validation::Block
        def difficulty
          return true  if Bitcoin.network_name == :testnet3
          block.bits == next_bits_required || [block.bits, next_bits_required]
        end
      end
    end

    it "should get depth" do
      @store.get_depth.should == 3
    end

    it "should report depth as -1 if store is empty" do
      @store.reset
      @store.get_depth.should == -1
    end

    it "should get head" do
      @store.get_head
        .should == @store.get_block("0000000098932356a236718829dd9e3eb0f9143317ab921333b1a203de336de4")
    end

    it "should get locator" do
      @store.get_locator.should == [
        "0000000098932356a236718829dd9e3eb0f9143317ab921333b1a203de336de4",
        "000000037b21cac5d30fc6fda2581cf7b2612908aed2abbcc429c45b0557a15f",
        "000000033cc282bc1fa9dcae7a533263fd7fe66490f550d80076433340831604",
        "00000007199508e34a9ff81e6ec0c477a4cccff2a4767a8eee39c11db367b008"]
    end

    it "should not store if there is no prev block" do
      @store.reset
      @store.store_block(@blk).should == [0, 2]
      @store.get_depth.should == -1
    end

    it "should check whether block is already stored" do
      @store.has_block(@blk.hash).should == false
      @store.store_block(@blk)
      @store.has_block(@blk.hash).should == true
    end

    it "should get block by depth" do
      @store.get_block_by_depth(0).hash.should ==
        P::Block.new(fixtures_file('testnet/block_0.bin')).hash
      @store.get_block_by_depth(1).hash.should ==
        P::Block.new(fixtures_file('testnet/block_1.bin')).hash
      @store.get_block_by_depth(2).hash.should ==
        P::Block.new(fixtures_file('testnet/block_2.bin')).hash
    end

    it "should store and retrieve all relevant block data for hash/json serialization" do
      (0..2).each do |i|
        expected = P::Block.new(fixtures_file("testnet/block_#{i}.bin")).to_hash
        @store.get_block_by_depth(i).to_hash.should == expected
      end
    end

    it "should get block by hash" do
      @store.get_block(
        "00000007199508e34a9ff81e6ec0c477a4cccff2a4767a8eee39c11db367b008").hash
        .should == P::Block.new(fixtures_file('testnet/block_0.bin')).hash
      @store.get_block(
        "000000033cc282bc1fa9dcae7a533263fd7fe66490f550d80076433340831604").hash
        .should == P::Block.new(fixtures_file('testnet/block_1.bin')).hash
      @store.get_block(
        "000000037b21cac5d30fc6fda2581cf7b2612908aed2abbcc429c45b0557a15f").hash
        .should == P::Block.new(fixtures_file('testnet/block_2.bin')).hash
    end

    it "should not get block" do
      @store.get_block("nonexistant").should == nil
    end

    it "should get block depth" do
      @store.get_block("00000007199508e34a9ff81e6ec0c477a4cccff2a4767a8eee39c11db367b008")
        .depth.should == 0
      @store.get_block("000000033cc282bc1fa9dcae7a533263fd7fe66490f550d80076433340831604")
        .depth.should == 1
      @store.get_block("000000037b21cac5d30fc6fda2581cf7b2612908aed2abbcc429c45b0557a15f")
        .depth.should == 2
    end

    it "should get prev block" do
      @store.get_block("00000007199508e34a9ff81e6ec0c477a4cccff2a4767a8eee39c11db367b008")
        .get_prev_block.should == nil
      @store.get_block("000000033cc282bc1fa9dcae7a533263fd7fe66490f550d80076433340831604")
        .get_prev_block.should ==
        @store.get_block("00000007199508e34a9ff81e6ec0c477a4cccff2a4767a8eee39c11db367b008")
    end

    it "should get next block" do
      @store.get_block("0000000098932356a236718829dd9e3eb0f9143317ab921333b1a203de336de4")
        .get_next_block.should == nil
      @store.get_block("00000007199508e34a9ff81e6ec0c477a4cccff2a4767a8eee39c11db367b008")
        .get_next_block.should ==
        @store.get_block("000000033cc282bc1fa9dcae7a533263fd7fe66490f550d80076433340831604")
    end

    it "should get block for tx" do
      @store.store_block(@blk)
      @store.get_block_by_tx(@blk.tx[0].hash).should == @blk
    end

    # TODO calling .is_a? on @store breaks it (?!?)
    if @store.class.name =~ /SequelStore/
      describe :transactions do

        it "should store tx" do
          @store.store_tx(@tx, false).should != false
        end
        
        it "should not store tx if already stored and return existing id" do
          id = @store.store_tx(@tx, false)
          @store.store_tx(@tx, false).should == id
        end

        it "should check if tx is already stored" do
          @store.has_tx(@tx.hash).should == false
          @store.store_tx(@tx, false)
          @store.has_tx(@tx.hash).should == true
        end

        it "should store hash160 for txout" do
          @store.store_tx(@tx, false)
          @store.get_tx(@tx.hash).out[0].hash160
            .should == "3129d7051d509424d23d533fa2d5258977e822e3"
        end

        it "should get tx" do
          @store.store_tx(@tx, false)
          @store.get_tx(@tx.hash).should == @tx
        end

        it "should not get tx" do
          @store.get_tx("nonexistant").should == nil
        end

        it "should get tx for txin" do
          @store.store_tx(@tx, false)
          @store.get_tx(@tx.hash).in[0].get_tx.should == @tx
        end

        it "should get prev out for txin" do
          tx = P::Tx.new(fixtures_file('rawtx-f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16.bin'))
          outpoint_tx = P::Tx.new(fixtures_file('rawtx-0437cd7f8525ceed2324359c2d0ba26006d92d856a9c20fa0241106ee5a597c9.bin'))
          @store.store_tx(outpoint_tx, false)
          @store.store_tx(tx, false)
          @store.get_tx(tx.hash).in[0].get_prev_out.should == outpoint_tx.out[0]
        end

        it "should get tx for txout" do
          @store.store_tx(@tx, false)
          @store.get_tx(@tx.hash).out[0].get_tx.should == @tx
        end

        it "should get next in for txin" do
          tx = P::Tx.new(fixtures_file('rawtx-f4184fc596403b9d638783cf57adfe4c75c605f6356fbc91338530e9831e9e16.bin'))
          outpoint_tx = P::Tx.new(fixtures_file('rawtx-0437cd7f8525ceed2324359c2d0ba26006d92d856a9c20fa0241106ee5a597c9.bin'))
          @store.store_tx(outpoint_tx, false)
          @store.store_tx(tx, false)
          @store.get_tx(outpoint_tx.hash).out[0].get_next_in.should == tx.in[0]
        end

        it "should store multisig tx and index hash160's" do
          *keys = Bitcoin::Key.generate, Bitcoin::Key.generate
          pk_script = Bitcoin::Script.to_multisig_script(1, keys[0].pub, keys[1].pub)
          txout = P::TxOut.new(1000, pk_script)
          @store.store_txout(0, txout, 0)
          keys.each do |key|
            hash160 = Bitcoin.hash160(key.pub)
            txouts = @store.get_txouts_for_hash160(hash160, true)
            txouts.size.should == 1
            txouts[0].pk_script.should == txout.pk_script
          end
        end

        it "should index output script type" do
          @store.store_tx(@tx, false)
          @store.get_tx(@tx.hash).out.first.type.should == :hash160
        end

      end
    end


    describe :txouts do

      before do
        @key = Key.generate
        @key2 = Key.generate
        @store.store_block(@blk)
        blk = create_block @blk.hash, true, [], @key
        @block = create_block blk.hash, true, [->(t) {
          create_tx(t, blk.tx.first, 0, [[50, @key2]]) }], @key
      end

      it "should get block for tx" do
        @store.get_tx(@block.tx[1].hash).get_block.hash.should == @block.hash
      end

      it "should get txouts for pk script" do
        script = @blk.tx[0].out[0].pk_script
        @store.get_txouts_for_pk_script(script)
          .should == [@blk.tx[0].out[0]]
      end

      it "should get txouts for hash160" do
        @store.get_txouts_for_hash160(@key2.hash160, true)
          .should == [@block.tx[1].out[0]]
      end

      it "should get txouts for address" do
        @store.get_txouts_for_address(@key2.addr, true)
          .should == [@block.tx[1].out[0]]
      end

      it "should get balance for address" do
        @store.get_balance(@key.addr).should == 0
        @store.get_balance(@key2.hash160).should == 50
      end

    end

    describe "validation" do

      before do
        @key = Bitcoin::Key.generate
        @store.store_block @blk
        @block = create_block @blk.hash, false, [], @key
        @tx = build_tx {|t| create_tx(t, @block.tx.first, 0, [[50, @key]]) }
        @tx.instance_eval { @in = [] }
      end

      it "should validate blocks" do
        @block.tx << @tx
        -> { @store.store_block(@block) }.should
          .raise(ValidationError).message.should =~ /mrkl_root/
      end

      it "should validate transactions for blocks added to main chain" do
        @store.store_block(@block)
        block = create_block @block.hash, false, [->(tx) {
            create_tx(tx, @block.tx.first, 0, [[50, @key]]) }], @key
        block.tx.last.in[0].prev_out_index = 5
        -> { @store.store_block(block) }.should
          .raise(ValidationError).message.should =~ /transactions_syntax/
      end

      it "should not validate transactions for blocks added to a side or orphan chain" do
        @store.store_block(@block)
        block = create_block @blk.hash, false, [->(tx) {
            create_tx(tx, @block.tx.first, 0, [[50, @key]]) }], @key
        @store.store_block(block).should == [5, 1]
      end

      if @store.class.name =~ /Sequel/

        it "should validate transactions" do
          @store.store_block @block
          -> { @store.store_tx(@tx, true) }.should.raise(ValidationError)
        end


        it "should validate transactions for new main blocks on reorg" do
          @store.store_block(@block)
          block = create_block @blk.hash, true, [->(tx) {
              create_tx(tx, @block.tx.first, 0, [[50, @key]]) }], @key
          block2 = create_block block.hash, false, [], @key
          -> { @store.store_block(block2) }.should
            .raise(ValidationError).message.should =~ /transactions_context/
        end

      end

      it "should skip validation" do
        @store.config[:skip_validation] = true
        @block.tx << @tx
        @store.store_block(@block).should == [5, 0]
      end

    end

  end

end
