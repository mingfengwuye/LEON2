



----------------------------------------------------------------------------
--  This file is a part of the LEON VHDL model
--  Copyright (C) 1999  European Space Agency (ESA)
--
--  This library is free software; you can redistribute it and/or
--  modify it under the terms of the GNU Lesser General Public
--  License as published by the Free Software Foundation; either
--  version 2 of the License, or (at your option) any later version.
--
--  See the file COPYING.LGPL for the full details of the license.


-----------------------------------------------------------------------------
-- Entity: 	dcom_uart
-- File:	dcom_uart.vhd
-- Author:	Jiri Gaisler - Gaisler Research
-- Description:	Asynchronous UART with baud-rate detection.
------------------------------------------------------------------------------

library IEEE;
use IEEE.std_logic_1164.all;
use IEEE.std_logic_unsigned."+";
use IEEE.std_logic_unsigned."-";
use IEEE.std_logic_unsigned.">";
use work.target.all;
use work.config.all;
use work.iface.all;
use work.macro.all;
use work.amba.all;
--pragma translate_off
use ieee.std_logic_unsigned.conv_integer;
use STD.TEXTIO.all;
--pragma translate_on

entity dcom_uart is
  port (
    rst    : in  std_logic;
    clk    : in  clk_type;
    apbi   : in  apb_slv_in_type;
    apbo   : out apb_slv_out_type;
    uarti  : in  dcom_uart_in_type;
    uarto  : out dcom_uart_out_type
  );
end; 
 
architecture rtl of dcom_uart is


type rxfsmtype is (idle, startbit, data, stopbit);
type txfsmtype is (idle, data, stopbit);


type uartregs is record
  rxen   	:  std_logic;	-- receiver enabled
  dready    	:  std_logic;	-- data ready
  rsempty   	:  std_logic;	-- receiver shift register empty (internal)
  tsempty   	:  std_logic;	-- transmitter shift register empty
  thempty   	:  std_logic;	-- transmitter hold register empty
  break  	:  std_logic;	-- break detected
  ovf    	:  std_logic;	-- receiver overflow
  frame     	:  std_logic;	-- framing error
  rhold 	:  std_logic_vector(7 downto 0);
  rshift	:  std_logic_vector(7 downto 0);
  tshift	:  std_logic_vector(10 downto 0);
  thold 	:  std_logic_vector(7 downto 0);


  txstate	:  txfsmtype;

  txclk 	:  std_logic_vector(2 downto 0);  -- tx clock divider
  txtick     	:  std_logic;	-- tx clock (internal)


  rxstate	:  rxfsmtype;

  rxclk 	:  std_logic_vector(2 downto 0); -- rx clock divider
  rxdb  	:  std_logic;   -- rx data filtering buffer
  rxtick     	:  std_logic;	-- rx clock (internal)

  tick     	:  std_logic;	-- rx clock (internal)
  scaler	:  std_logic_vector(17 downto 0);
  brate 	:  std_logic_vector(17 downto 0);

  tcnt  	:  std_logic_vector(1 downto 0); -- autobaud counter
  rxdb2  	:  std_logic;   -- delayed rx data
  rxf    	:  std_logic_vector(7 downto 0); --  rx data filtering buffer
  fedge  	:  std_logic;   -- rx falling edge
end record;

signal r, rin : uartregs;

begin

  uartop : process(rst, r, apbi, uarti )
  variable rdata : std_logic_vector(31 downto 0);
  variable scaler : std_logic_vector(17 downto 0);
  variable rxclk, txclk : std_logic_vector(2 downto 0);
  variable rxd : std_logic;
  variable v : uartregs;

  begin

    v := r;
    v.txtick := '0'; v.rxtick := '0'; v.tick := '0'; rdata := (others => '0');

-- scaler

-- pragma translate_off
    if not is_x(r.scaler) then		-- avoid warnings at reset time
-- pragma translate_on
      if r.tcnt = "11" then
        scaler := r.scaler - 1;
      else
        scaler := r.scaler + 1;
      end if;
-- pragma translate_off
    end if;
-- pragma translate_on

    v.rxdb2 := r.rxdb;
    if r.tcnt /= "11" then
      if (r.rxdb2 and not r.rxdb) = '1' then v.fedge := '1'; end if;
      if (r.fedge) = '1' then 
	v.scaler := scaler;
	if (r.scaler(17) and not r.scaler(16)) = '1' then
	  v.fedge := '0'; v.tcnt := "00";
	  v.scaler := "111111111111111011";
	end if;
      end if;
      if (r.rxdb2 and r.fedge and not r.rxdb) = '1' then
	if ieee.std_logic_unsigned.">"(r.brate(17 downto 4),r.scaler(17 downto 4)) then 
	  v.brate := r.scaler; v.tcnt := "00";
	end if;
	v.scaler := "111111111111111011";
	if (r.brate(17 downto 4) = r.scaler(17 downto 4)) then 
	  v.tcnt := r.tcnt + 1;
	  if r.tcnt = "10" then 
	    v.brate := "0000" & r.scaler(17 downto 4);
	    v.scaler := v.brate; v.rxen := '1';
          end if;
        end if;
      end if;
    else
      if (r.break and r.rxdb2) = '1' then
	v.scaler := "111111111111111011";
	v.brate := (others => '1'); v.tcnt := "00";
 	v.break := '0'; v.rxen := '0';
      end if;
    end if;

    if r.rxen = '1' then
      v.scaler := scaler;
      v.tick := scaler(15) and not r.scaler(15);
      if v.tick = '1' then v.scaler := r.brate; end if;
    end if;

-- read/write registers

    if uarti.read = '1' then
      v.dready := '0';
    end if;

    case apbi.paddr(3 downto 2) is
--    when "00" => 
--      rdata(7 downto 0) := r.rhold; 
--      if (apbi.psel and apbi.penable and (not apbi.pwrite)) = '1' then 
--	v.dready := '0';
--      end if;
    when "01" => 
      rdata(6 downto 0) := r.frame & '0' & r.ovf & 
		r.break & r.thempty & r.tsempty & r.dready;
--pragma translate_off
      if DEBUGUART then rdata(2 downto 1) := "11"; end if;
--pragma translate_on
    when "10" => 
      rdata(1 downto 0) := (r.tcnt(1) or r.tcnt(0)) & r.rxen;
    when others => 
      rdata(17 downto 0) := r.brate;
    end case;

    if (apbi.psel and apbi.penable and apbi.pwrite) = '1' then
      case apbi.paddr(3 downto 2) is
      when "01" =>
	v.frame  := apbi.pwdata(6);
	v.ovf 	 := apbi.pwdata(4);
	v.break  := apbi.pwdata(3);
      when "10" => 
	v.tcnt 	 := apbi.pwdata(1) & apbi.pwdata(1);
	v.rxen 	 := apbi.pwdata(0);
      when "11" =>
	v.brate := apbi.pwdata(17 downto 0);
	v.scaler := apbi.pwdata(17 downto 0);
      when others =>
      end case;
    end if;

-- tx clock

-- pragma translate_off
    if not is_x(r.txclk) then		-- avoid warnings at reset time
-- pragma translate_on
      txclk := r.txclk + 1;
-- pragma translate_off
    else
      txclk := (others => 'X');
    end if;
-- pragma translate_on
    if r.tick = '1' then
      v.txclk := txclk;
      v.txtick := r.txclk(2) and not txclk(2);
    end if;

-- rx clock

-- pragma translate_off
    if not is_x(r.rxclk) then		-- avoid warnings at reset time
-- pragma translate_on
      rxclk := r.rxclk + 1;
-- pragma translate_off
    else
      rxclk := (others => 'X');
    end if;
-- pragma translate_on
    if r.tick = '1' then
      v.rxclk := rxclk;
      v.rxtick := r.rxclk(2) and not rxclk(2);
    end if;

-- filter rx data

    v.rxf := r.rxf(6 downto 0) & uarti.rxd;
    if ((r.rxf(7) & r.rxf(7) & r.rxf(7) & r.rxf(7) & r.rxf(7) & r.rxf(7) &
	 r.rxf(7)) = r.rxf(6 downto 0))
    then v.rxdb := r.rxf(7); end if;

    rxd := r.rxdb;

-- transmitter operation

    case r.txstate is
    when idle =>	-- idle state
      if (r.txtick = '1') then v.tsempty := '1'; end if;
      if (r.rxen and (not r.thempty) and r.txtick) = '1' then 
	v.tshift := "10" & r.thold & '0'; v.txstate := data; 
	v.thempty := '1';
	v.tsempty := '0'; v.txclk := "00" & r.tick; v.txtick := '0';
      end if;
    when data =>	-- transmitt data frame
      if r.txtick = '1' then
	v.tshift := '1' & r.tshift(10 downto 1);
        if r.tshift(10 downto 1) = "1111111110" then
	v.tshift(0) := '1'; v.txstate := stopbit;
	end if;
      end if;
    when stopbit =>	-- transmitt stop bit
      if r.txtick = '1' then
	v.tshift := '1' & r.tshift(10 downto 1); v.txstate := idle;
      end if;

    end case;

-- writing of tx data register must be done after tx fsm to get correct
-- operation of thempty flag

    if uarti.write = '1' then
      v.thold := uarti.data(7 downto 0); v.thempty := '0';
    end if;

-- receiver operation

    case r.rxstate is
    when idle =>	-- wait for start bit
      if ((not r.rsempty) and not r.dready) = '1' then
	v.rhold := r.rshift; v.rsempty := '1'; v.dready := '1';
      end if;
      if (r.rxen and r.rxdb2 and (not rxd)) = '1' then
	v.rxstate := startbit; v.rshift := (others => '1'); v.rxclk := "100";
	if v.rsempty = '0' then v.ovf := '1'; end if;
	v.rsempty := '0'; v.rxtick := '0';
      end if;
    when startbit =>	-- check validity of start bit
      if r.rxtick = '1' then
	if rxd = '0' then 
	  v.rshift := rxd & r.rshift(7 downto 1); v.rxstate := data;
	else
	  v.rxstate := idle;
        end if;
      end if;
    when data =>	-- receive data frame
      if r.rxtick = '1' then
	v.rshift := rxd & r.rshift(7 downto 1); 
	if r.rshift(0) = '0' then
	v.rxstate := stopbit;
	end if;
      end if;
    when stopbit =>	-- receive stop bit
      if r.rxtick = '1' then
	if rxd = '1' then
	  v.rsempty := '0';
	  if v.dready = '0' then
	    v.rhold := r.rshift; v.rsempty := '1'; v.dready := '1';
	  end if;
	else
	  if r.rshift = "00000000" then
	    v.break := '1'; 		 -- break
	  else
	    v.frame := '1'; 		 -- framing error
	  end if;
	  v.rsempty := '1';
	end if;
        v.rxstate := idle;
      end if;

    end case;

-- reset operation

    if rst = '0' then 
      v.frame := '0'; v.rsempty := '1';
      v.ovf := '0'; v.break := '0'; v.thempty := '1';
      v.tsempty := '1'; v.dready := '0'; v.fedge := '0';
      v.txstate := idle; v.rxstate := idle; v.tshift(0) := '1';
      v.scaler := "111111111111111011"; v.brate := (others => '1'); 
      v.rxen := '0'; v.tcnt := "00";
      v.txclk := (others => '0'); v.rxclk := (others => '0');
    end if;

-- update registers

    rin <= v;

-- drive outputs
    uarto.txd <= r.tshift(0);
    uarto.dready <= r.dready;
    uarto.tsempty <= r.tsempty;
    uarto.thempty <= r.thempty;
    uarto.lock <= r.tcnt(1) and  r.tcnt(0);
    uarto.enable <= r.rxen;
    uarto.data <= r.rhold;

    apbo.prdata <= rdata;

  end process;

  regs : process(clk)
  begin if rising_edge(clk) then r <= rin; end if; end process;


end;
