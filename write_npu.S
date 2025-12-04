    lui   t0, 0x70001
    addi  t0, t0, 0      # base img_in = 0x70001

    lui   t1, 0x60000
    addi  t1, t1, 0      # base dcache = 0x600000

    li    t3, 60         # cnt
img_loop:
    beqz  t3, img_done
    lw    t2, 0(t1)
    sw    t2, 0(t0)
    addi  t1, t1, 4      
    addi  t0, t0, 1      
    addi  t3, t3, -1
    j     img_loop
img_done:
	
    
    li    t4, 10            # count of channels
    lui   s0, 0x60000
    addi  s0, s0, 2000
c1_loop:
	li    t3, 3
    beqz  t4, c1_done
    lui   t0,0x70002
    addi  t0, t0, 0
w1_loop:
    beqz  t3, w1_done
    lw    t2, 0(t1)
    sw    t2, 0(t0)
    addi  t1, t1, 4
    addi  t0, t0, 1
    addi  t3, t3, -1  
    j     w1_loop
w1_done:
    lui   t5, 0x70005
    li    t6, 1
    sw    t6, 0(t5)         # trigger signal
    li    t3, 182
    
k1_loop:
    beqz  t3, k1_done   
    addi  t3, t3, -1    # push the data
    lui   t5, 0x70007
    addi  t5, t5, 8
    poll_valid:
    lw    t6, 0(t5)
    beqz  t6, poll_valid    # wait until valid
    lui   t5, 0x70007
    addi  t5, t5, 12
    lw    t6, 0(t5)         # read the output
    sw    t6, 0(s0)         # save the output
    addi  s0, s0, 1
    lui   t5, 0x70005
    li    t6, 4
    sw    t6, 0(t5)         # save_done
    j     k1_loop
k1_done:
    addi  t4, t4, -1
    j     c1_loop
c1_done:

    lui   t5, 0x70005
    li    t6, 8
    sw    t6, 0(t5)         # next layer signal
    li    t4, 10            # count of channels
    lui   s0, 0x60000
    addi  s0, s0, 2000
c2_loop:
	li    t3, 3
    beqz  t4, c2_done
    lui   t0, 0x70002
    addi  t0, t0, 0
w2_loop:
    beqz  t3, w2_done
    lw    t2, 0(t1)
    sw    t2, 0(t0)
    addi  t1, t1, 4
    addi  t0, t0, 1
    addi  t3, t3, -1  
    j     w2_loop
w2_done:
    li    t3, 45
    lui   t5, 0x70001
in_loop:
    beqz  t3, in_done
    lw    t2, 0(s0)
    sw    t2, 0(t5)
    addi  t5, t5, 1
    addi  s0, s0, 4
    addi  t3, t3, -1
    j     in_loop
in_done:
    lw    t2, 0(s0)
    sw    t2, 0(t5)
    addi  t5, t5, 1
    addi  s0, s0, 2
    lui   t5, 0x70005
    li    t6, 1
    sw    t6, 0(t5)         # trigger signal
    li    t3, 132
    lui   t2, 0x60000
    addi  t2, t2, 2000
k2_loop:
    beqz  t3, k2_done   
    addi  t3, t3, -1    # push the data
    lui   t5, 0x70007
    addi  t5, t5, 8
    poll_valid2:
    lw    t6, 0(t5)
    beqz  t6, poll_valid2    # wait until valid
   
    lui   t5, 0x70005
    li    t6, 4
    sw    t6, 0(t5)         # save_done
    j     k2_loop
k2_done:
    addi  t4, t4, -1
    j     c2_loop
c2_done:
    lui   t5, 0x70005
    li    t6, 8
    sw    t6, 0(t5)         # next layer signal

    lui   t0,0x70003
    addi  t0, t0, 0
    li    t3, 132
f1_loop:
    beqz  t3, f1_done
    lw    t2, 0(t1)
    sw    t2, 0(t0)
    addi  t1, t1, 4     
    addi  t0, t0, 1      
    addi  t3, t3, -1
    lui   t5, 0x70005
    li    t6, 16
    sw    t6, 0(t5)         # trigger signal
    lui   t5, 0x70007
    addi  t5, t5, 16
    poll_fcn:
    lw    t6, 0(t5)
    beqz  t6, poll_fcn    # wait until valid
    lui   t5, 0x70005
    li    t6, 2
    sw    t6, 0(t5)         # next
    j     f1_loop
f1_done:

    lui   t0, 0x70004
    addi  t0, t0, 0
    li    t3, 3
f2_loop:
    beqz  t3, f2_done
    lw    t2, 0(t1)
    sw    t2, 0(t0)
    addi  t1, t1, 4     
    addi  t0, t0, 1     
    addi  t3, t3, -1
    j     f2_loop
f2_done:
    
    
poll_done:
    lui   t0, 0x70007    
    addi  t0, t0, 20
    li    t2, 0
    lw    t2, 0(t0)      
    beqz  t2, poll_done

   
    lui   t0, 0x70007   
    addi  t0, t0, 4
    lw    t2, 0(t0)
    lui   t4, 0x60000
    addi  t4, t4, 1999
	sw    t2, 0(t4)
    
stop:
    j     stop
    