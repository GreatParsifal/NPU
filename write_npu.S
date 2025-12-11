    lui   s0, 0x70001    
    addi  s0, s0, 0      # base img_in 
    
    lui   s1, 0x70002    
    addi  s1, s1, 0      # base weight_conv1

    lui   s1, 0x60000
    addi  s1, s1, 0      # base image = 0x600000

    lui   s2, 0x600F0
    addi  s2, s2, 0      # base conv_weight = 0x600F00

    lui   s3, 0x60000
    addi  s3, s3, 2000   # base save = 0x6007D0

    li    t3, 10         # channel_cnt
conv1_chan_loop:
    beqz  t3, conv1_chan_done
    lui   t5, 0x70005
    li    t6, 16
    sw    t6, 0(t5)         # clear weight signal
    li    t4, 3
w_conv1_loop:
    beqz  t4, w_conv1_done
    lw    t2, 0(s2)
    sw    t2, 0(s1)
    addi  s2, s2, 3
    addi  t4, t4, -1
    j     w_conv1_loop      # load weights
w_conv1_done:
    li    t4, 2
    li    t0, 14            # column_cnt
conv1_col_loop:             # column loop
inn_conv1_loop:
    beqz  t0, conv1_col_done
    beqz  t4, inn_conv1_done
    lw    t2, 0(s0)
    sw    t2, 0(s1)         # load input
    addi  s0, s0, 3
    addi  t4, t4, -1
    li    t5, 0x70005
    li    t6, 1
    sw    t6, 0(t5)         # trigger signal
    lui   t5, 0x70007
    poll_valid2:
    lw    t6, 0(t5)
    beqz  t6, poll_valid2    # wait until valid
    j     inn_conv1_loop    # load 2 input at first
inn_conv1_done:
    li    t1, 4             # readout cnt
    li    t4, 13            # row cnt
conv1_row_loop:
    beqz  t4, conv1_row_done
    lw    t2, 0(s0)
    sw    t2, 0(s1)         # load input
    addi  s0, s0, 3
    addi  t4, t4, -1
    li    t5, 0x70005
    li    t6, 1
    sw    t6, 0(t5)         # trigger signal
    lui   t5, 0x70007
    poll_valid1:
    lw    t6, 0(t5)
    beqz  t6, poll_valid1    # wait until valid

    beqz  t1, jump_readout
    lui   t5, 0x70006
    lw    t6, 0(t5)         # read the output
    sw    t6, 0(s3)         # save the output
    addi  s3, s3, 4
jump_readout:
    addi  t1, t1, -1
    j     conv1_row_loop
conv1_row_done:
    addi  t0, t0, -1
    j     conv1_col_loop
conv1_col_done:
    addi  t3, t3, -1
    j     conv1_chan_loop
conv1_chan_done:
	

stop:
    j     stop
    