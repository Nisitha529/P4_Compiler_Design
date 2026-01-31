import Ethernet::*;
import StructDefines::*;
typedef union tagged {
    struct {
        Bit#(48) dmac;
    } SetDmac0ReqT;
    struct {
        Bit#(0) unused;
    } Drop20ReqT;
    struct {
        Bit#(0) unused;
    } NoAction1ReqT;
} ForwardParam deriving (Bits, Eq, FShow);
typedef union tagged {
    struct {
        Bit#(32) nhop_ipv4;
        Bit#(9) _port;
    } SetNhop0ReqT;
    struct {
        Bit#(0) unused;
    } Drop10ReqT;
    struct {
    } NoAction5ReqT;
} Ipv4LpmParam deriving (Bits, Eq, FShow);
import Ethernet::*;
import StructDefines::*;
typedef union tagged {
    struct {
        Bit#(48) smac;
    } RewriteMac0ReqT;
    struct {
        Bit#(0) unused;
    } Drop30ReqT;
    struct {
        Bit#(0) unused;
    } NoAction0ReqT;
} SendFrameParam deriving (Bits, Eq, FShow);
