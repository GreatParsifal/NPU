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
	
    lui   t0,0x70002
    addi  t0, t0, 0
    li    t4, 10
    lui   t2,0x60000
    addi  t2, t2, 2000
c1_loop:
	li    t3, 3
    beqz  t4, c1_done
    lui   t5, 0x70005
    li    t6, 1
    sw    t6, 0(t5)         # start signal
    lui   t5, 0x70006
    addi  t5, t5, 0
k1_loop:
    beqz  t3, k1_done   
    lw    t2, 0(t1)     
    sw    t2, 0(t0)
    addi  t1, t1, 4      
    addi  t0, t0, 1      
    addi  t3, t3, -1    # push the data
    lui   t5, 0x70007
    addi  t5, t5, 2
    poll_valid:
    lw    t6, 0(t5)
    beqz  t6, poll_valid    # wait until valid
    lui   t5, 0x70007
    addi  t5, t5, 4
    lw    t6, 0(t5)         # read the output
    sw    t6, 0(t0)         # save the output
    addi  t2, t0, 4
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
    lui   t0,0x70002
    addi  t0, t0, 0
    li    t4, 10
    lui   t2,0x60000
    addi  t2, t2, 2000
c2_loop:
	li    t3, 3
    beqz  t4, c2_done
    lui   t5, 0x70006
    addi  t5, t5, 0
k2_loop:
    beqz  t3, k2_done   
    lw    t2, 0(t1)     
    sw    t2, 0(t0)
    addi  t1, t1, 4      
    addi  t0, t0, 1      
    addi  t3, t3, -1    # push the data
    lui   t5, 0x70007
    addi  t5, t5, 2
    poll_valid2:
    lw    t6, 0(t5)
    beqz  t6, poll_valid2    # wait until valid
    lui   t5, 0x70007
    addi  t5, t5, 4
    lw    t6, 0(t5)         # read the output
    sw    t6, 0(t0)         # save the output
    addi  t2, t0, 4
    lui   t5, 0x70005
    li    t6, 4
    sw    t6, 0(t5)         # save_done
    j     k2_loop
k2_done:
    addi  t4, t4, -1
c2_done:


lui t0,0x70003
    addi  t0, t0, 0
    li    t3, 3
f1_loop:
    beqz  t3, f1_done
    lw    t2, 0(t1)
    sw    t2, 0(t0)
    addi  t1, t1, 4      # src += 4 (next 32-bit word)
    addi  t0, t0, 1      # dest += 4 (must be +4, not +1)
    addi  t3, t3, -1
    j     f1_loop
f1_done:
lui t0,0x70004
    addi  t0, t0, 0
    li    t3, 3
f2_loop:
    beqz  t3, f2_done
    lw    t2, 0(t1)
    sw    t2, 0(t0)
    addi  t1, t1, 4      # src += 4 (next 32-bit word)
    addi  t0, t0, 1      # dest += 4 (must be +4, not +1)
    addi  t3, t3, -1
    j     f2_loop
f2_done:
    
lui t0,0x70005
    addi  t0, t0, 1     
    sw    t2, 0(t0)

    
poll_done:
    lui   t0, 0x70007    
    addi  t0, t0, 0
    li    t2, 0
    lw    t2, 0(t0)      
    beqz  t2, poll_done

   
    lui   t0, 0x70007   
    addi  t0, t0, 1
    addi  t4, t1, 2000
    lw    t2, 0(t0) 
	sw    t2, 0(t4)
    
stop:
    j     stop
    