import DefaultValue::*;
typedef struct{
    Bit#(4) padding;
    Bit#(32) dstAddr;
} RoutingReqT deriving (Bits, FShow);
instance DefaultValue#(RoutingReqT);
    defaultValue = unpack(0);
endinstance
typedef struct {
    Bit#(2) _action;
} RoutingRspT deriving (Bits, FShow);
