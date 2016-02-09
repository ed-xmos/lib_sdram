// Copyright (c) 2016, XMOS Ltd, All rights reserved
#include <platform.h>
#include <stdio.h>
#include <stdlib.h>
#include "sdram.h"

/*
 * Put an sdram slice into slot 4 of the xCore200 slice-kit board.
 */


void application(streaming chanend c_server) {
#define BUF_WORDS (8)
  unsigned read_buffer[BUF_WORDS];
  unsigned write_buffer[BUF_WORDS];
  unsigned * movable read_buffer_pointer = read_buffer;
  unsigned * movable write_buffer_pointer = write_buffer;

#define MEM_SIZE_EXP    23 //2^n 32b words

  //1<<20 is halfway point for 64Mb memory
  //1<<22 is halfway point for 256Mb memory
  //unsigned base_addr = (1 << 22) - 4; // 2^(12b row + 8b col + 2b bank) = 2M words 32b = 64Mb
  unsigned base_addr = (1 << MEM_SIZE_EXP) - 4; // 2^(13b row + 9b col + 2b bank) = 8M words 32b = 256Mb

  s_sdram_state sdram_state;
  sdram_init_state(c_server, sdram_state);

#define FILL_BUFF_SIZE  128

  unsigned fill[FILL_BUFF_SIZE];
  for(unsigned i=0;i<FILL_BUFF_SIZE;i++) fill[i] = 0xdeadbeef;

  unsigned * movable write_buffer_pointer_fill = fill;

  //bottom bit
  sdram_write(c_server, sdram_state, 0, FILL_BUFF_SIZE, move(write_buffer_pointer_fill));
  sdram_complete(c_server, sdram_state, write_buffer_pointer_fill);


  //top bit = makes it spill over
  sdram_write(c_server, sdram_state, (1<<MEM_SIZE_EXP) - (FILL_BUFF_SIZE/2), FILL_BUFF_SIZE, move(write_buffer_pointer_fill));
  sdram_complete(c_server, sdram_state, write_buffer_pointer_fill);

  printf("Mem filled\n");


  for(unsigned i=0;i<BUF_WORDS;i++){
    write_buffer_pointer[i] = i;
    read_buffer_pointer[i] = 0;
  }

  sdram_write(c_server, sdram_state, base_addr, BUF_WORDS, move(write_buffer_pointer));
  sdram_read (c_server, sdram_state, base_addr, BUF_WORDS, move( read_buffer_pointer));

  sdram_complete(c_server, sdram_state, write_buffer_pointer);
  sdram_complete(c_server, sdram_state,  read_buffer_pointer);

  printf("Read/write done\n");

  for(unsigned i=0;i<BUF_WORDS;i++){
    printf("%08x\t %d\t %08x\n", base_addr + i, i, read_buffer_pointer[i]);
    if(read_buffer_pointer[i] != write_buffer_pointer[i]){
     // printf("SDRAM demo fail.\n");
     //_Exit(1);
    }
  }

  sdram_read (c_server, sdram_state, 0, BUF_WORDS, move( read_buffer_pointer));
  sdram_complete(c_server, sdram_state,  read_buffer_pointer);

  for(unsigned i=0;i<BUF_WORDS;i++){
    printf("%08x\t %d\t %08x\n", 0 + i, i, read_buffer_pointer[i]);
  }

  printf("SDRAM demo complete.\n");
  _Exit(0);
}

on tile[1] : out buffered port:32   sdram_dq_ah                 = XS1_PORT_16B;
on tile[1] : out buffered port:32   sdram_cas                   = XS1_PORT_1J;
on tile[1] : out buffered port:32   sdram_ras                   = XS1_PORT_1I;
on tile[1] : out buffered port:8    sdram_we                    = XS1_PORT_1K;
on tile[1] : out port               sdram_clk                   = XS1_PORT_1L;
on tile[1] : clock                  sdram_cb                    = XS1_CLKBLK_1;

int main() {
  streaming chan c_sdram[1];
  par {
      on tile[1]:sdram_server(c_sdram, 1,
              sdram_dq_ah,
              sdram_cas,
              sdram_ras,
              sdram_we,
              sdram_clk,
              sdram_cb,
#if 0
              2, 128, 16, 8, 12, 2, 64, 4096, 6); //64Mb
#else
                2, 256, 16, 9, 13, 2, 64, 8192, 6); //256Mb
#endif
                //Note clock div 4 gives (500/ (4*2)) = 62.5MHz
    on tile[1]: application(c_sdram[0]);
    //on tile[1]: par(int i=0;i<6;i++) while(1);
  }
  return 0;
}
