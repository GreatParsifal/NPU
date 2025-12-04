
## Top Module: npu
### Description:
  High-level pipeline wiring conv1 -> conv2 -> fc1 -> fc2 (from README).
  This is a simple sequential controller that triggers each stage one by one.

### address definition:
#### port name: addr
#### width: 3 + 12 = 15
#### Write Configuration (wea = 1)
##### addr[14:12] defines the state of npu
    000: banned
    001: receiving img_in_flat
    010: receiving w_conv_flat (9*1)
    011: receiving cur_w_stream
    100: receiving fc2_w
    101: other operations (trigger, rst, require ...)
    110: ...(undef)
##### addr[11:0] represents:
    address of weight or iamge pixel when addr[14:12] < 3'b101;
    type of operation when addr[14:12] == 3'b101.
        addr[0]: trigger,
        addr[1]: rst_n,
        addr[2]: save_done,
        addr[3]: host_next_layer,
        addr[4]: ce (for partial_sum),
        addr[5]: clear_conv,
        addr[6]: clear_sum

#### Read Configuration (wea = 0)
##### addr[14:12] are not cared
##### addr[11:0]
    12'd0: douta <= {31'd0, done_reg};
    12'd4: douta <= {{8{result_reg[23]}}, result_reg};
    12'd8: douta <= {31'd0, pixel_valid};
    12'd12: douta <= {23'b0, conv1_out_pixel};
