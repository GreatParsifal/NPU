    lui   t0, 0x70003
    addi  t0, t0, 0      # base dest = 0x700030

    lui   t1, 0x60000
    addi  t1, t1, 0      # base src = 0x600000

    li    t3, 330
fc1_loop:
    beqz  t3, fc1_done
    lw    t2, 0(t1)
    sw    t2, 0(t0)
    addi  t1, t1, 4      # src += 4 (next 32-bit word)
    addi  t0, t0, 1      # dest += 4 (must be +4, not +1)
    addi  t3, t3, -1
    j     fc1_loop
fc1_done:
	lui t0,0x70004
    addi  t0, t0, 0
    
	li    t3, 3
fc2_loop:
    beqz  t3, fc2_done
    lw    t2, 0(t1)
    sw    t2, 0(t0)
    addi  t1, t1, 4      # src += 4 (next 32-bit word)
    addi  t0, t0, 1      # dest += 4 (must be +4, not +1)
    addi  t3, t3, -1
    j     fc2_loop
fc2_done:

lui t0,0x70000
    addi  t0, t0, 0
li    t3, 33
in_loop:
    beqz  t3, in_done
    lw    t2, 0(t1)
    sw    t2, 0(t0)
    addi  t1, t1, 4      # src += 4 (next 32-bit word)
    addi  t0, t0, 1      # dest += 4 (must be +4, not +1)
    addi  t3, t3, -1
    j     in_loop
in_done:
	lui t0,0x70005
    addi  t0, t0, 4     
    li    t2, 1
    sw    t2, 0(t0)

    # -------------------------------
    # 轮询 done: 读 sel=5, idx=0，直到 bit0=1
poll_done:
    lui   t0, 0x70005    # ACC_BASE + (5<<12 | 0) << 2 = 0x70005000
    addi  t0, t0, 0
    lw    t2, 0(t0)
    andi  t2, t2, 1      # 检查 bit0
    beqz  t2, poll_done

    # -------------------------------
    # 读结果: 读 sel=5, idx=1
    lui   t0, 0x70005    # ACC_BASE + (5<<12 | 1) << 2 = 0x70005004
    add   t0, t0, 4
    addi  t4, t1, 2000
    lw    t5, 0(t0) 
	sw    t5, 0(t4)
    
stop:
    j     stop
    