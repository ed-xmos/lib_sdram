// Copyright (c) 2014-2017, XMOS Ltd, All rights reserved
#include <platform.h>
#include <stdio.h>
#include <stdlib.h>
#include "sdram.h"

//For XS1, put an SDRAM slice into 'square' slot of A16 slice kit
//For XS2 (xCORE200) put an SDRAM slice into the 'triangle' slot of tile 0 of the XP-SKC-X200 slice kit
//If using 256Mb slice, then define USE_256Mb below, otherwise leave commented out

#define USE_256Mb   1 //Else will assume 64Mb

#define DEBUG       1

unsigned c = 0xffffffff;
static void reset_super_pattern(unsigned x) {
  c = x;
}

static unsigned super_pattern() {
  crc32(c, 0xff, 0x82F63B78);
  return c;
}


unsigned application(streaming chanend c_server) {
#define BUF_WORDS (512)
  unsigned read_buffer[BUF_WORDS];
  unsigned write_buffer[BUF_WORDS];
  unsigned * movable read_buffer_pointer = read_buffer;
  unsigned * movable write_buffer_pointer = write_buffer;

  s_sdram_state sdram_state;
  printf("pre...\n");
  sdram_init_state(c_server, sdram_state);
  printf("post...\n");

  //Fill the memory initially with known pattern and verify
  for(unsigned i=0;i<BUF_WORDS;i++){
    write_buffer_pointer[i] = 0xdeadbeef;
    read_buffer_pointer[i] = 0; //And clear read pointer
  }
  sdram_write(c_server, sdram_state, 0x0, BUF_WORDS, move(write_buffer_pointer));
  printf("wr_start\n");
  sdram_complete(c_server, sdram_state, write_buffer_pointer);
  printf("wr_complete\n");

  sdram_read (c_server, sdram_state, 0x0, BUF_WORDS, move( read_buffer_pointer));
  printf("rd_start\n");
  sdram_complete(c_server, sdram_state,  read_buffer_pointer);
  printf("rd_complete\n");

  for(unsigned i=0;i<BUF_WORDS;i++) {
    //printf("%08x %d\n", read_buffer_pointer[i], i);
    if(read_buffer_pointer[i] != write_buffer_pointer[i]){
#if DEBUG
      printf("SDRAM demo fail.\nValue written at long word adress 0x%x is %08x but value read %08x\n", i, write_buffer_pointer[i], read_buffer_pointer[i]);
#endif 
      return(1);
    }
  }

  //Fill the memory with address super pattern and verify
  reset_super_pattern(0xffffffff);
  for(unsigned i=0;i<BUF_WORDS;i++){
    write_buffer_pointer[i] = super_pattern();
    read_buffer_pointer[i] = 0; //And clear read pointer
  }

  sdram_write(c_server, sdram_state, 0x0, BUF_WORDS, move(write_buffer_pointer));
  sdram_complete(c_server, sdram_state, write_buffer_pointer);

  sdram_read (c_server, sdram_state, 0x0, BUF_WORDS, move( read_buffer_pointer));
  sdram_complete(c_server, sdram_state,  read_buffer_pointer);

  for(unsigned i=0;i<BUF_WORDS;i++){
    //printf("%08x %d\n", read_buffer_pointer[i], i);
    if(read_buffer_pointer[i] != write_buffer_pointer[i]){
#if DEBUG
      printf("SDRAM demo fail.\nValue written at long word adress 0x%x is %08x but value read %08x\n", i, write_buffer_pointer[i], read_buffer_pointer[i]);
#endif
      return(1);
    }
  }
  return (0);
}


//Use port mapping according to slicekit used
#ifdef __XS2A__
//Triangle slot tile 0 for XU216
#define      SERVER_TILE            0
on tile[SERVER_TILE] : out buffered port:32   sdram_dq_ah                 = XS1_PORT_16B;
on tile[SERVER_TILE] : out buffered port:32   sdram_cas                   = XS1_PORT_1J;
on tile[SERVER_TILE] : out buffered port:32   sdram_ras                   = XS1_PORT_1I;
on tile[SERVER_TILE] : out buffered port:8    sdram_we                    = XS1_PORT_1K;
on tile[SERVER_TILE] : out port               sdram_clk                   = XS1_PORT_1L;
on tile[SERVER_TILE] : clock                  sdram_cb                    = XS1_CLKBLK_2;
#else
//Square slot on A16 slicekit
#define      SERVER_TILE            1
on tile[SERVER_TILE] : out buffered port:32   sdram_dq_ah                 = XS1_PORT_16A;
on tile[SERVER_TILE] : out buffered port:32   sdram_cas                   = XS1_PORT_1B;
on tile[SERVER_TILE] : out buffered port:32   sdram_ras                   = XS1_PORT_1G;
on tile[SERVER_TILE] : out buffered port:8    sdram_we                    = XS1_PORT_1C;
on tile[SERVER_TILE] : out port               sdram_clk                   = XS1_PORT_1F;
on tile[SERVER_TILE] : clock                  sdram_cb                    = XS1_CLKBLK_2;
#endif

int main() {
  streaming chan c_sdram[1];
  par {
    on tile[SERVER_TILE]:
    {
      for(unsigned clock_divider = 3; clock_divider <= 10; clock_divider++){
        for(unsigned whole_cycles_read_delay = 0; whole_cycles_read_delay <= 2; whole_cycles_read_delay++){
          for(unsigned sample_delay_edge = 0; sample_delay_edge <= 1; sample_delay_edge++){
            for(unsigned pad_delay_n = 0; pad_delay_n <= 5; pad_delay_n++) {
              unsigned result = 2;
              printf("DIV:%d\tN:%d\tSDEL:%d\tPDEL:%d", clock_divider, whole_cycles_read_delay, sample_delay_edge, pad_delay_n);
              par{
                sdram_server(c_sdram, 1,
                  sdram_dq_ah,
                  sdram_cas,
                  sdram_ras,
                  sdram_we,
                  sdram_clk,
                  sdram_cb,
#if USE_256Mb
                  2, 256, 16, 9, 13, 2, 64, 8192, clock_divider, pad_delay_n, whole_cycles_read_delay, sample_delay_edge); //IS45S16160D 256Mb option or similar
#else
                  2, 128, 16, 8, 12, 2, 64, 4096, clock_divider, pad_delay_n, whole_cycles_read_delay, sample_delay_edge); //Uses IS42S16400D 64Mb part supplied on SDRAM slice
#endif
                {
                  result = application(c_sdram[0]);
                  sdram_shutdown(c_sdram[0]);
                }
                {
                  if (clock_divider == 3) par(int i=0 ;i<4 ;i++) while(1); //Consume the remaining MHz
                  else par(int i=0 ;i<6 ;i++) while(1); //Consume the remaining MHz
                }
              }
              printf(" - %d", result ? "FAIL\n" : "PASS\n");
            } 
          }
        }
      }
      printf("SDRAM timing sweep complete\n");
      _Exit(0);
    }
  }
  return 0;
}
