`include "inc.h"


//*******************************************************************************
//  S Y N T H E Z I A B L E      S D R A M     C O N T R O L L E R    C O R E
//
//  This core adheres to the GNU Public License  
// 
//  This is a synthesizable Synchronous DRAM controller Core.  As it stands,
//  it is ready to work with 8Mbyte SDRAMs, organized as 2M x 32 at 100MHz
//  and 125MHz. For example: Samsung KM432S2030CT,  Fujitsu MB81F643242B.
//
//  The core has been carefully coded so as to be "platform-independent".  
//  It has been successfully compiled and simulated under three separate
//  FPGA/CPLD platforms:
//      Xilinx Foundation Base Express V2.1i
//      Altera Max+PlusII V9.21
//      Lattice ispExpert V7.0
//  
//  The interface to the host (i.e. microprocessor, DSP, etc) is synchronous
//  and supports ony one transfer at a time.  That is, burst-mode transfers
//  are not yet supported.  In may ways, the interface to this core is much
//  like that of a typical SRAM.  The hand-shaking between the host and the 
//  SDRAM core is done through the "sdram_busy_l" signal generated by the 
//  core.  Whenever this signal is active low, the host must hold the address,
//  data (if doing a write), size and the controls (cs, rd/wr).  
//
//  Connection Diagram:
//  SDRAM side:
//  sd_wr_l                     connect to -WR pin of SDRAM
//  sd_cs_l                     connect to -CS pin of SDRAM
//  sd_ras_l                    connect to -RAS pin of SDRAM
//  sd_cas_l                    connect to -CAS pin of SDRAM
//  sd_dqm[3:0]                 connect to the DQM3,DQM2,DQM1,DQM0 pins
//  sd_addx[10:0]               connect to the Address bus [10:0]
//  sd_data[31:0]               connect to the data bus [31:0]
//  sd_ba[1:0]                  connect to BA1, BA0 pins of SDRAM
//   
//  HOST side:
//  mp_addx[22:0]               connect to the address bus of the host. 
//                              23 bit address bus give access to 8Mbyte
//                              of the SDRAM, as byte, half-word (16bit)
//                              or word (32bit)
//  mp_data_in[31:0]            Unidirectional bus connected to the data out
//                              of the host. To use this, enable 
//                              "databus_is_unidirectional" in INC.H
//  mp_data_out[31:0]           Unidirectional bus connected to the data in 
//                              of the host.  To use this, enable
//                              "databus_is_unidirectional" in INC.H
//  mp_data[31:0]               Bi-directional bus connected to the host's
//                              data bus.  To use the bi-directionla bus,
//                              disable "databus_is_unidirectional" in INC.H
//  mp_rd_l                     Connect to the -RD output of the host
//  mp_wr_l                     Connect to the -WR output of the host
//  mp_cs_l                     Connect to the -CS of the host
//  mp_size[1:0]                Connect to the size output of the host
//                              if there is one.  When set to 0
//                              all trasnfers are 32 bits, when set to 1
//                              all transfers are 8 bits, and when set to
//                              2 all xfers are 16 bits.  If you want the
//                              data to be lower order aligned, turn on
//                              "align_data_bus" option in INC.H
//  sdram_busy_l                Connect this to the wait or hold equivalent
//                              input of the host.  The host, must hold the
//                              bus if it samples this signal as low.
//  sdram_mode_set_l            When a write occurs with this set low,
//                              the SDRAM's mode set register will be programmed
//                              with the data supplied on the data_bus[10:0].
//
//
//  Author:  Jeung Joon Lee  joon.lee@quantum.com,  cmosexod@ix.netcom.com
//  
//*******************************************************************************
//
//  Hierarchy:
//
//  SDRAM.V         Top Level Module
//  HOSTCONT.V      Controls the interfacing between the micro and the SDRAM
//  SDRAMCNT.V      This is the SDRAM controller.  All data passed to and from
//                  is with the HOSTCONT.
//  optional
//  MICRO.V         This is the built in SDRAM tester.  This module generates 
//                  a number of test logics which is used to test the SDRAM
//                  It is basically a Micro bus generator. 
//  
/*
*/ 



module sdramcnt(	
		// system level stuff
			sys_rst_l,
			sys_clk,
		
		// SDRAM connections
			sd_wr_l,
		    sd_cs_l,
			sd_ras_l,
			sd_cas_l,
			sd_dqm,
			
			// Host Controller connections
	    	do_mode_set,
	  		do_read,
            do_write,
            doing_refresh,
            sd_addx_mux,
            sd_addx10_mux,
            sd_rd_ena,
            sd_data_ena,
            modereg_cas_latency,
            modereg_burst_length,
            mp_data_mux,
			decoded_dqm,
            do_write_ack,
            do_read_ack,
            do_modeset_ack,
            pwrup,

			// debug
            next_state,
			autorefresh_cntr,
			autorefresh_cntr_l,
			cntr_limit

		);



// ****************************************
//
//   I/O  DEFINITION
//
// ****************************************


// System level stuff
input	        sys_rst_l;
input	        sys_clk;

// SDRAM connections
output	        sd_wr_l;
output	        sd_cs_l;
output	        sd_ras_l;
output	        sd_cas_l;
output	 [3:0]  sd_dqm;

// Host Controller connections
input           do_mode_set;
input           do_read;
input           do_write;
output          doing_refresh;
output  [1:0]   sd_addx_mux;
output  [1:0]   sd_addx10_mux;
output          sd_rd_ena;
output          sd_data_ena;
input   [2:0]   modereg_cas_latency;
input   [2:0]   modereg_burst_length;
output          mp_data_mux;
input	[3:0]	decoded_dqm;
output          do_write_ack;
output          do_read_ack;
output          do_modeset_ack;
output			pwrup;

// Debug
output  [3:0]   next_state;
output	[3:0]	autorefresh_cntr;
output			autorefresh_cntr_l;
output	[12:0]	cntr_limit;

// ****************************************
//
// Memory Elements 
//
// ****************************************
//
reg     [3:0]	next_state;
reg     [7:0]   refresh_timer;
reg 	        sd_wr_l;
reg		        sd_cs_l;
reg		        sd_ras_l;
reg		        sd_cas_l;
reg     [3:0]   sd_dqm;
reg     [1:0]   sd_addx_mux;
reg     [1:0]   sd_addx10_mux;
reg             sd_data_ena;
reg		        pwrup;			// this variable holds the power up condition
reg     [12:0]  refresh_cntr;   // this is the refresh counter
reg				refresh_cntr_l;	// this is the refresh counter reset signal
reg     [3:0]   burst_length_cntr;
reg             burst_cntr_ena;
reg             sd_rd_ena;      // read latch gate, active high
reg     [12:0]  cntr_limit;
reg     [3:0]   modereg_burst_count;
reg     [2:0]   refresh_state;
reg             mp_data_mux;
wire            do_refresh;     // this bit indicates autorefresh is due
reg             doing_refresh;  // this bit indicates that the state machine is 
                                // doing refresh.
reg     [3:0]   autorefresh_cntr;
reg             autorefresh_cntr_l;
reg             do_write_ack;
reg             do_read_ack;
reg             do_modeset_ack;
reg             do_refresh_ack;



// State Machine
always @(posedge sys_clk or negedge sys_rst_l)
  if (~sys_rst_l) begin
    next_state	<= `state_powerup;
    autorefresh_cntr_l <= `LO;
	refresh_cntr_l  <= `LO;
    pwrup       <= `HI;
    sd_wr_l     <= `HI;
    sd_cs_l     <= `HI;
    sd_ras_l    <= `HI;
    sd_cas_l    <= `HI;
    sd_dqm      <= 4'hF;
    sd_data_ena <= `LO;
    sd_addx_mux <= 2'b10;           // select the mode reg default value
    sd_addx10_mux <= 2'b11;         // select 1 as default
    sd_rd_ena   <= `LO;
    mp_data_mux <= `LO;
//    refresh_cntr<= 13'h0000;
    burst_cntr_ena <= `LO;          // do not enable the burst counter
    doing_refresh  <= `LO;
    do_write_ack <= `LO;            // do not ack as reset default
    do_read_ack  <= `LO;            // do not ack as reset default
    do_modeset_ack <= `LO;          // do not ack as reset default
    do_refresh_ack <= `LO;
  end 
  else case (next_state)
    // Power Up state
    `state_powerup:  begin
        next_state  <= `state_precharge;
        sd_wr_l     <= `HI;
        sd_cs_l     <= `HI;
    	sd_ras_l    <= `HI;
    	sd_cas_l    <= `HI;
        sd_dqm      <= 4'hF;
        sd_data_ena <= `LO;
        sd_addx_mux <= 2'b10;
        sd_rd_ena   <= `LO;
        pwrup       <= `HI;         // this is the power up run
        burst_cntr_ena <= `LO;      // do not enable the burst counter
		refresh_cntr_l <= `HI;		// allow the refresh cycle counter to count
     end

    // PRECHARGE both banks        	
    `state_precharge:  begin
        sd_wr_l     <= `LO;
        sd_cs_l     <= `LO;
    	sd_ras_l    <= `LO;
    	sd_cas_l    <= `HI;
        sd_dqm      <= 4'hF;
        sd_addx10_mux <= 2'b11;      // A10 = 1'b1   
        doing_refresh <= `HI;        // indicate that we're doing refresh
		next_state  <= `state_delay_Trp;
    end  

    // Delay Trp 
    // this delay is needed to meet the minimum precharge to new command
    // delay.  For most parts, this is 20nS, which means you need 1 clock cycle
    // of NOP at 100MHz
    `state_delay_Trp:  begin
        sd_wr_l     <= `HI;
        sd_cs_l     <= `HI;
      	sd_ras_l    <= `HI;
        if ( (refresh_cntr == cntr_limit) & (pwrup == `HI) ) begin
            doing_refresh <= `LO;                // refresh cycle is done
            refresh_cntr_l  <= `LO;             // ..reset refresh counter
            next_state <= `state_modeset;      // if this was power-up, then go and set mode reg
        end else begin
            doing_refresh <= `HI;        // indicate that we're doing refresh
            next_state	 <= `state_auto_refresh;
	    end
    end


    // Autorefresh
    `state_auto_refresh: begin
        sd_wr_l     <= `HI;
        sd_cs_l     <= `LO;
    	sd_ras_l    <= `LO;
    	sd_cas_l    <= `LO;
        sd_dqm      <= 4'hF;
        sd_addx10_mux <= 2'b01;      // A10 = 0   
        next_state  <= `state_auto_refresh_dly;
        autorefresh_cntr_l  <= `HI;  //allow delay cntr to tick
        do_refresh_ack <= `HI;      // acknowledge refresh request
     end    

    // This state generates the Trc delay.
    // this delay is the delay from the refresh command to the next valid command
    // most parts require this to be 60 to 70nS.  So at 100MHz, we need at least
    // 6 NOPs.  
    `state_auto_refresh_dly:  begin
          sd_wr_l     <= `HI;
          sd_cs_l     <= `HI;
          sd_ras_l    <= `HI;
          sd_cas_l    <= `HI;
          sd_dqm      <= 4'hF;
          sd_addx10_mux <= 2'b00;      // select ROW again A10 = A20   
        // Wait for Trc
        if (autorefresh_cntr == 4'h6) begin  
              autorefresh_cntr_l <= `LO;  // reset Trc delay counter
              // Check if all refresh is done
              if ((refresh_cntr == cntr_limit) & (pwrup == `LO))   begin  
                   doing_refresh <= `LO;             // refresh cycle is done
                   refresh_cntr_l  <= `LO;           // ..reset refresh counter
                   if (do_write | do_read)
                       next_state <= `state_set_ras; // go service a pending read or write if any
                   else
                       next_state <= `state_idle;    // if there are no peding RD or WR, then go to idle state
              end         
              // IF refresh cycles not done yet..
              else
                   next_state <= `state_precharge; 
        end
        // If Trc has not expired
        else begin
              next_state <= `state_auto_refresh_dly;
              do_refresh_ack <= `LO;
        end
    end


    // MODE SET state
    `state_modeset:  begin
        next_state  <= `state_delay_Trsc;
        sd_wr_l     <= `LO;
        sd_cs_l     <= `LO;
        sd_ras_l    <= `LO;
        sd_cas_l    <= `LO;
        sd_addx_mux <= 2'b10;
        sd_addx10_mux <= 2'b10;
    end

    // Delay Trsc
    // this delay is need to meet the Trsc timing.  This is the mode reg set to
    // valid command delay.  For most parts this is 20nS.  So at 100MHz, there
    // needs to be at least 1 NOP cycle.
    `state_delay_Trsc:  begin
        sd_wr_l     <= `HI;
        sd_cs_l     <= `HI;
        sd_ras_l    <= `HI;
        sd_cas_l    <= `HI;
        doing_refresh <= `LO;   // deassert 
        do_modeset_ack <= `HI;  // acknowledge the mode set request
        if (pwrup)
           pwrup    <= `LO;                 // ..no more in power up mode
        sd_addx_mux <= 2'b00;   // select ROW (A[19:10]) of mp_addx to SDRAM 
        sd_addx10_mux <= 2'b00; // select ROW (A[20])    "      "
        next_state  <= `state_idle;
    end


    // IDLE state
    `state_idle:  begin
        sd_wr_l     <= `HI;
        sd_cs_l     <= `HI;
        sd_ras_l	<= `HI;
        sd_cas_l	<= `HI;
        sd_dqm      <= 4'hF;
        sd_data_ena <= `LO;         // turn off the data bus drivers
        mp_data_mux <= `LO;         // drive the SD data bus with normal data
        if (do_write | do_read )          
            next_state <= `state_set_ras;
         else if (do_mode_set) begin
            next_state <= `state_modeset;
            doing_refresh <= `HI;		// techincally we're not doing refresh, but this signal is used to prevent the do_write be deasserted
        end                             // by the mode_set command.
        else if (do_refresh) begin
            next_state <= `state_precharge;
			refresh_cntr_l <= `HI;		// allow refresh cycle counter to count up
		end
    end    

    // SET RAS state
    `state_set_ras:  begin
        sd_cs_l     <= `LO;     // enable SDRAM 
        sd_ras_l    <= `LO;     // enable the RAS
        next_state  <= `state_ras_dly;   // wait for a bit
    end

    // RAS delay state.  
    // This delay is needed to meet Trcd delay.  This is the RAS to CAS delay.
    // for most parts this is 20nS.  So for 100MHz operation, there needs to be 
    // at least 1 NOP cycle.
    `state_ras_dly:  begin
        sd_cs_l     <= `HI;     // disable SDRAM 
        sd_ras_l    <= `HI;     // disble the RAS
        sd_addx_mux <= 2'b01;   // select COLUMN 
        sd_addx10_mux <= 2'b01; // select COLUMN 
        if (do_write)  begin
            sd_data_ena <= `HI;     // turn on  the data bus drivers
            sd_dqm      <= decoded_dqm;  // masks the data which is meant to be
            next_state  <= `state_write;      // if write, do the write      
        end else begin
            sd_dqm      <= 4'h0;
            next_state  <= `state_set_cas;    // if read, do the read
        end
    end

    // WRITE state
    `state_write:  begin
        sd_cs_l     <= `LO;     // enable SDRAM 
        sd_cas_l    <= `LO;     // enable the CAS
        sd_wr_l     <= `LO;     // enable the write
        do_write_ack<= `HI;     // acknowledge the write request
        next_state  <= `state_cool_off;
    end

    // SET CAS state
    `state_set_cas:  begin
        sd_cs_l     <= `LO;
        sd_cas_l    <= `LO;
        next_state  <= `state_cas_latency1;        
    end

    `state_cas_latency1: begin
        sd_cs_l     <= `HI;     // disable CS
        sd_cas_l    <= `HI;     // disable CAS
        if (modereg_cas_latency==3'b010)  begin
           next_state <= `state_read;            // 2 cycles of lantency done.
           burst_cntr_ena <= `HI;                // enable he burst lenght counter
        end else
           next_state <= `state_cas_latency2;    // 3 cycles of latency      
    end

    `state_cas_latency2:  begin
        next_state <= `state_read;
        burst_cntr_ena <= `HI;      // enable the burst lenght counter
    end

    `state_read:  begin
        if (burst_length_cntr == modereg_burst_count) begin
            burst_cntr_ena <= `LO;  // done counting;
            sd_rd_ena      <= `LO;     // done with the reading
            next_state     <= `state_cool_off;
            do_read_ack    <= `HI;  // acknowledge the read request
        end else
           sd_rd_ena  <= `HI;          // enable the read latch on the next state		
    end

    `state_cool_off:  begin
        sd_wr_l     <= `HI;
        sd_cs_l     <= `HI;
        sd_ras_l	<= `HI;
        sd_cas_l	<= `HI;
        sd_dqm      <= 4'hF;
        sd_addx_mux <= 2'b00;   // send ROW (A[19:10]) of mp_addx to SDRAM 
        sd_addx10_mux <= 2'b00; // send ROW (A[20])    "      "
                mp_data_mux <= `HI;         // drive the SD data bus with all zeros
        if (do_write)
            do_write_ack<= `LO;         // done acknowledging the write request
        if (do_read)
            do_read_ack <= `LO;         // done acknowledging the read request
        if (do_mode_set)
            do_modeset_ack <= `LO;
        next_state  <= `state_idle;
    end

  endcase
  

// This counter is used to generate a delay right after the 
// auto-refresh command is issued to the SDRAM
always @(posedge sys_clk or negedge autorefresh_cntr_l)
  if (~autorefresh_cntr_l)
    autorefresh_cntr <= 4'h0;
  else
    autorefresh_cntr <= autorefresh_cntr + 1;



// This mux selects the cycle limit value for the 
// auto refresh counter
always @(pwrup)
  case (pwrup)
      `HI:      cntr_limit <= `power_up_ref_cntr_limit;
      default:  cntr_limit <= `auto_ref_cntr_limit;
  endcase
  
  
//
// BURST LENGHT COUNTER
//
// This is the burst length counter.  
always @(posedge sys_clk or negedge burst_cntr_ena)
  if (~burst_cntr_ena)
     burst_length_cntr <= 3'b000;   // reset whenever 'burst_cntr_ena' is low
  else
     burst_length_cntr <= burst_length_cntr + 1;

//
// REFRESH_CNTR
//
always @(posedge sys_clk or negedge refresh_cntr_l)
  if (~refresh_cntr_l)
     refresh_cntr <= 13'h0000;
  else if (next_state  == `state_auto_refresh)
	 refresh_cntr <= refresh_cntr + 1;

//
// BURST LENGTH SELECTOR
//
always @(modereg_burst_length)
   case (modereg_burst_length)
      3'b000:  modereg_burst_count <= 4'h1;
      3'b001:  modereg_burst_count <= 4'h2;
      3'b010:  modereg_burst_count <= 4'h4;
      default  modereg_burst_count <= 4'h8;
   endcase


//
// REFRESH Request generator
//
assign do_refresh = (refresh_state == `state_halt);


always @(posedge sys_clk or negedge sys_rst_l)
  if (~sys_rst_l) begin
     refresh_state <= `state_count;
     refresh_timer <= 8'h00;
  end 
  else case (refresh_state)
     // COUNT
     // count up the refresh interval counter. If the
     // timer reaches the refresh-expire time, then go next state
     `state_count:  
        if (refresh_timer != `RC) begin
           refresh_timer <= refresh_timer + 1;
           refresh_state <= `state_count;
        end else begin
           refresh_state <= `state_halt;
           refresh_timer <= 0;
		end
    
     // HALT
     // wait for the SDRAM to complete any ongoing reads or
     // writes.  If the SDRAM has acknowledged the do_refresh,
     // (i.e. it is now doing the refresh)
     // then go to next state 
     `state_halt: 
/*        if (next_state==`state_auto_refresh     | 
            next_state==`state_auto_refresh_dly |
            next_state==`state_precharge )  
           refresh_state <= `state_reset;
*/
          if (do_refresh_ack)
            refresh_state <= `state_count;        

     // RESET
     // if the SDRAM refresh is completed, then reset the counter
     // and start counting up again.
     `state_reset:
        if (next_state==`state_idle) begin
           refresh_state <= `state_count;
           refresh_timer <= 8'h00;
        end
  endcase
           

endmodule

