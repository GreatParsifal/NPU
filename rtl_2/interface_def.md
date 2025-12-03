
## Module: npu
### Description:
  High-level pipeline wiring conv1 -> conv2 -> fc1 -> fc2 (from README).
  This is a simple sequential controller that triggers each stage one by one.

### address definition:
#### port name: addr
#### width: 3 + 12 = 15
##### addr[14:12] defines the state of npu
    000: receiving input image
    001: receiving w_conv (3*3)
    010: receiving layer idx (0 for conv1, 1 for conv2)
    011: receiving w_fcn1 (132*10)
    100: receiving w_fcn2 (10*1)
    101: other operations (trigger, rst, require ...)
##### addr[11:0] represents:
    address of weight or iamge pixel when addr[14:12] < 3'b101;
    type of operation when addr[14:12] == 3'b101.
        12'd0: rst
        12'd1: trigger
        12'd2: require
