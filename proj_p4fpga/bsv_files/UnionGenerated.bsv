import Ethernet::*;
import StructDefines::*;
typedef union tagged {
    struct {
        Bit#(0) unused;
    } NopReqT;
    struct {
        Bit#(9) port;
    } ForwardReqT;
    struct {
        Bit#(0) unused;
    } NoAction0ReqT;
} RoutingParam deriving (Bits, Eq, FShow);
import Ethernet::*;
import StructDefines::*;
