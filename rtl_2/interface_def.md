
## Top Module: npu
### Description:
  High-level pipeline wiring conv1 -> conv2 -> fc1 -> fc2 (from README).
  This is a simple sequential controller that triggers each stage one by one.

### address definition:
#### port name: addra
#### width: 3
#### Write Configuration (wea = 1)
##### addra[2:0] defines the state of npu
    000: banned
    001: laoding in_img
    010: loading w_conv
    011: loading fcn_in and fcn_w
    100: other operations (trigger, rst, require ...)
    101: ...(undef)
##### dina represents:
    input data, when addra < 3'b100;
    definition of dina when addra == 3'b100:
        dina[0]: trigger,
        dina[1]: next_layer,
        dina[2]: clear_pe

#### Read Configuration (wea = 0)
##### addr[2:0]
    3'd1: douta <= {31'd0, done_reg};
    3'd2: douta <= conv1_out_pack;
    3'd3: douta <= {31'd0, pixel_valid};
    3'd4: douta <= {23'b0, conv2_out_pixel};
