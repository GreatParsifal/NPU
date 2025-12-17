    lui   s0, 0x70001
    addi  s0, s0, 0      # base in_data
    
    lui   s2, 0x60000
    addi  s2, s2, 240     # base conv_weight = 0x600F00
    
    lui   s1, 0x70002    
    addi  s1, s1, 0      # base weight_conv1

    lui   s4, 0x60000
    addi  s4, s4, 0      # base image = 0x600000

    lui   s3, 0x60000
    addi  s3, s3, 2000   # base save = 0x6007D0

    li    t3, 10         # channel_cnt
conv1_chan_loop:
    beqz  t3, conv1_chan_done
    
    li    t0, 14            # column_cnt
conv1_col_loop:             # column loop
    lui   t5, 0x70004
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
    addi  s2, s2, -9
    li    t4, 2             # pre-load count
    lui   t5, 0x70004
    li    t6, 8
    sw    t6, 0(t5)         # clear input signal
    lui   t5, 0x70004
    li    t6, 4
    sw    t6, 0(t5)         # clear pe signal
inn_conv1_loop:
    beqz  t0, conv1_col_done
    beqz  t4, inn_conv1_done
    addi  t5, s4, -3
    lw    t2, 0(t5)         # in_img[0]
    srl   t2, t2, 24
    addi  t5, t5, 15        # get in_img[1] to [31:24]
    lw    t6, 0(t5)         # in_img[1]
    srl   t6, t6, 24
    sll   t6, t6, 8
    add  t2, t2, t6
    addi  t5, t5, 15
    lw    t6, 0(t5)         # in_img[2]
    srl   t6, t6, 24
    sll   t6, t6, 16
    add  t2, t2, t6
    sw    t2, 0(s0)         # load input
    addi  s4, s4, 1
    addi  t4, t4, -1

    lui    t5, 0x70004
    li    t6, 1
    sw    t6, 0(t5)         # trigger signal
    lui   t5, 0x70007
    poll_valid1:
    lw    t6, 0(t5)
    beqz  t6, poll_valid1    # wait until valid
    j     inn_conv1_loop    # load 2 input at first
inn_conv1_done:
    li    t1, 4             # readout cnt
    li    t4, 13            # row cnt
    lui   t5, 0x70004
    li    t6, 32
    sw    t6, 0(t5)         # clear package signal
conv1_row_loop:
    beqz  t4, conv1_row_done

    addi  t5, s4, -3
    lw    t2, 0(t5)
    srl   t2, t2, 24
    addi  t5, t5, 15
    lw    t6, 0(t5)
    srl   t6, t6, 24
    sll   t6, t6, 8
    add  t2, t2, t6
    addi  t5, t5, 15
    lw    t6, 0(t5)
    srl   t6, t6, 24
    sll   t6, t6, 16
    add  t2, t2, t6
    sw    t2, 0(s0)         # load input
    addi  s4, s4, 1
    addi  t4, t4, -1

    lui    t5, 0x70004
    li    t6, 1
    sw    t6, 0(t5)         # trigger signal

    lui   t5, 0x70007
    poll_valid2:
    lw    t6, 0(t5)
    beqz  t6, poll_valid2    # wait until valid

    addi  t1, t1, -1
    beqz  t1, readout
    j     conv1_row_loop
readout:
    lui   t5, 0x70006       # sel output
    lw    t6, 0(t5)         # read the output
    sw    t6, 0(s3)         # save the output
    addi  s3, s3, 4         # save addr add 4

    lui   t5, 0x70004
    li    t6, 32
    sw    t6, 0(t5)         # clear package signal

    li    t1, 4             # readout cnt reset
    j     conv1_row_loop
conv1_row_done:
    addi  s4, s4, 15

    addi  t0, t0, -1

    lui   t5, 0x70006       # sel output
    lw    t6, 0(t5)         # read the last output[7:0]
    sw    t6, 0(s3)         # save the output
    addi  s3, s3, 1         # save addr add 1, [31:8] will be covered at next sw
    j     conv1_col_loop
conv1_col_done:
    addi  t3, t3, -1
    lui   s4, 0x60000       # reset image base addr
    addi  s2, s2, 9
    j     conv1_chan_loop
conv1_chan_done:            # finished conv1 calculation, conv2 start

    lui   t5, 0x70004
    li    t6, 2
    sw    t6, 0(t5)         # host_next_state signal

    lui   s2, 0x60000
    addi  s2, s2, 332       # conv2 weight base addr

    lui   s4, 0x60000
    addi  s4, s4, 2000      # conv2 input base addr

    lui   s3, 0x60000
    addi  s3, s3, 2000   
    li    t3, 10         # channel_cnt
conv2_chan_loop:
    beqz  t3, conv2_chan_done

    li    s5, 0x60000    # addr for conv1 result
    li    s5, 2000
    li    s5, 500
    li    t4, 2
    li    t0, 14            # column_cnt
conv2_col_loop:             # column loop
    lui   t5, 0x70004
    li    t6, 16
    sw    t6, 0(t5)         # clear weight signal

    li    t4, 3
w_conv2_loop:
    beqz  t4, w_conv2_done
    lw    t2, 0(s2)
    sw    t2, 0(s1)
    addi  s2, s2, 3
    addi  t4, t4, -1
    j     w_conv2_loop      # load weights
w_conv2_done:
    addi  s2, s2, -9

    lui   t5, 0x70004
    li    t6, 8
    sw    t6, 0(t5)         # clear input signal
inn_conv2_loop:
    beqz  t0, conv2_col_done
    beqz  t4, inn_conv2_done
    addi  t5, s4, -3
    lw    t2, 0(t5)         # in_img[0]
    srl   t2, t2, 24
    addi  t5, t5, 15        # get in_img[1] to [31:24]
    lw    t6, 0(t5)         # in_img[1]
    srl   t6, t6, 24
    sll   t6, t6, 8
    add  t2, t2, t6
    addi  t5, t5, 15
    lw    t6, 0(t5)         # in_img[2]
    srl   t6, t6, 24
    sll   t6, t6, 16
    add  t2, t2, t6
    sw    t2, 0(s0)         # load input
    addi  s4, s4, 1
    addi  t4, t4, -1
    lui    t5, 0x70004
    li    t6, 1
    sw    t6, 0(t5)         # trigger signal
    lui   t5, 0x70007
    poll_valid3:
    lw    t6, 0(t5)
    beqz  t6, poll_valid3    # wait until valid
    j     inn_conv2_loop    # load 2 input at first
inn_conv2_done:
   
    li    t4, 13            # row cnt
conv2_row_loop:
    beqz  t4, conv2_row_done
    addi  t5, s4, -3
    lw    t2, 0(t5)         # in_img[0]
    srl   t2, t2, 24
    addi  t5, t5, 15        # get in_img[1] to [31:24]
    lw    t6, 0(t5)         # in_img[1]
    srl   t6, t6, 24
    sll   t6, t6, 8
    add  t2, t2, t6
    addi  t5, t5, 15
    lw    t6, 0(t5)         # in_img[2]
    srl   t6, t6, 24
    sll   t6, t6, 16
    add  t2, t2, t6
    sw    t2, 0(s0)         # load input
    addi  s4, s4, 1
    addi  t4, t4, -1
    lui    t5, 0x70004
    li    t6, 1
    sw    t6, 0(t5)         # trigger signal
    lui   t5, 0x70007
    poll_valid4:
    lw    t6, 0(t5)
    beqz  t6, poll_valid4    # wait until valid

    lui   t5, 0x70006
    lw    t6, 0(t5)         # read the output
    li    t1, 10            # first time no add
    beq   t3, t1, jump_add
    lw    t5, 0(s5)         # load previous sum
    add   t6, t6, t5        # accumulate
    sw    t6, 0(s5)         # save the output
    addi  s5, s5, 4
jump_add:
    sw    t6, 0(s5)         # save the output
    addi  s5, s5, 4
    j     conv2_row_loop
conv2_row_done:
    addi  t0, t0, -1
    addi  s4, s4, 13
    j     conv2_col_loop
conv2_col_done:
    addi  t3, t3, -1
    j     conv2_chan_loop
conv2_chan_done:

    lui   s3, 0x60000
    addi  s3, s3, 2000
    addi  s3, s3, 1000
    li    s5, 0x600009C4
    li    t0, 3       # group cnt
fcn1_loop:
    beqz  t0, last_fcn1
    li    t1, 132   # fc1 input cnt
fcn1_input_loop:
    beqz  t1, fcn1_input_done
    lui   t5, 0x70003
    lw    t2, 0(s5)
    sw    t2, 0(t5)       # load input
    addi  s5, s5, 1
    lw    t2, 0(s2)
    sw    t2, 0(s1)       # load weight
    addi  s2, s2, 3
    lui    t5, 0x70004
    li    t6, 1
    sw    t6, 0(t5)         # trigger signal
    addi  t1, t1, -1
    j     fcn1_input_loop
fcn1_input_done:
    li    t5, 0x70006
    lw    t6, 0(t5)         # read the output
    sw    t6, 0(s3)         # save the output
    addi  s3, s3, 3
    addi  t0, t0, -1
    j fcn1_input_loop
last_fcn1:

    li    t1, 132   # fc1 input cnt
fcn1_input_loop2:
    beqz  t1, fcn1_input_done2
    lui   t5, 0x70003
    lw    t2, 0(s5)
    sw    t2, 0(t5)       # load input
    addi  s5, s5, 2
    lw    t2, 0(s2)
    sw    t2, 0(s1)       # load weight
    addi  s2, s2, 2
    lui    t5, 0x70004
    li    t6, 1
    sw    t6, 0(t5)         # trigger signal
    addi  t1, t1, -1
    j     fcn1_input_loop2
fcn1_input_done2:
    lui   t5, 0x70006
    lw    t6, 0(t5)         # read the output
    sw    t6, 0(s3)         # save the output
    addi  s3, s3, 1

    addi  s3, s3, -10
    li    t0, 5
fcn2_loop:
    beqz  t0, fcn2_done
    lui   t5, 0x70003
    lw    t2, 0(s3)
    sw    t2, 0(t5)         # load input
    addi  s3, s3, 2
    lw    t2, 0(s2)
    sw    t2, 0(s1)         # load weight
    addi  s2, s2, 2
    addi  t0, t0, -1 
fcn2_done:
    lui   t5, 0x70006
    lui   s3, 0x60000
    addi  s3, s3, 2000
    addi  s3, s3, 1000
    addi  s3, s3, 100
    lw    t6, 0(t5)         # read the output
    sw    t6, 0(s3)         # save the output
stop:
    j     stop
    