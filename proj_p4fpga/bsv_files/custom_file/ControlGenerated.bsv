import Library::*;
import StructDefines::*;
import UnionDefines::*;
import ConnectalTypes::*;
import Table::*;
import Engine::*;
import Pipe::*;
import Lists::*;
`include "TieOff.defines"
`include "Debug.defines"
`include "SynthBuilder.defines"
`include "MatchTable.defines"
typedef enum {
    NOP0,
    FORWARD0,
    NOACTION1
} RoutingActionT deriving (Bits, Eq, FShow);
`MATCHTABLE_SIM(26, 36, 2, _routing)
typedef Table#(3, MetadataRequest, RoutingParam, ConnectalTypes::RoutingReqT, ConnectalTypes::RoutingRspT) RoutingTable;
typedef MatchTable#(1, 26, 256, SizeOf#(ConnectalTypes::RoutingReqT), SizeOf#(ConnectalTypes::RoutingRspT)) RoutingMatchTable;
`SynthBuildModule1(mkMatchTable, String, RoutingMatchTable, mkMatchTable_Routing)
instance Table_request #(ConnectalTypes::RoutingReqT);
    function ConnectalTypes::RoutingReqT table_request(MetadataRequest data);
        ConnectalTypes::RoutingReqT v = defaultValue;
        if (data.meta.hdr.ethernet matches tagged Valid .ethernet) begin
            let dstAddr = ethernet.hdr.dstAddr;
            v = ConnectalTypes::RoutingReqT {dstAddr: dstAddr, padding: 0};
        end
        return v;
    endfunction
endinstance
instance Table_execute #(ConnectalTypes::RoutingRspT, RoutingParam, 3);
    function Action table_execute(ConnectalTypes::RoutingRspT resp, MetadataRequest metadata, Vector#(3, FIFOF#(Tuple2#(MetadataRequest, RoutingParam))) fifos);
        action
        case (unpack(resp._action)) matches
        endcase
        endaction
    endfunction
endinstance
typedef Engine#(1, MetadataRequest, RoutingParam) NoActionAction;
// INST extern count cnt.count
// INST (9) standard_metadata.egress_port; = port;
typedef Engine#(1, MetadataRequest, RoutingParam) ForwardAction;
instance Action_execute #(RoutingParam);
    function ActionValue#(MetadataRequest) step_1 (MetadataRequest meta, RoutingParam param);
        actionvalue
            $display("(%0d) step 1: ", $time, fshow(meta));
            return meta;
        endactionvalue
    endfunction
endinstance
// INST extern count cnt.count
typedef Engine#(1, MetadataRequest, RoutingParam) NopAction;
instance Action_execute #(RoutingParam);
    function ActionValue#(MetadataRequest) step_1 (MetadataRequest meta, RoutingParam param);
        actionvalue
            $display("(%0d) step 1: ", $time, fshow(meta));
            return meta;
        endactionvalue
    endfunction
endinstance
// =============== control ingress ==============
interface Ingress;
    interface PipeIn#(MetadataRequest) prev;
    interface PipeOut#(MetadataRequest) next;
    method Action _routing_add_entry(ConnectalTypes::RoutingReqT key, ConnectalTypes::RoutingRspT value);
    method Action set_verbosity(int verbosity);
endinterface
module mkIngress (Ingress);
    `PRINT_DEBUG_MSG
    FIFOF#(MetadataRequest) entry_req_ff <- mkFIFOF;
    FIFOF#(MetadataRequest) entry_rsp_ff <- mkFIFOF;
    FIFOF#(MetadataRequest) _routing_req_ff <- mkFIFOF;
    FIFOF#(MetadataRequest) _routing_rsp_ff <- mkFIFOF;
    FIFOF#(MetadataRequest) exit_req_ff <- mkFIFOF;
    FIFOF#(MetadataRequest) exit_rsp_ff <- mkFIFOF;
    Control::NoActionAction noAction_action <- mkEngine(toList(vec(step_1)));
    Control::ForwardAction forward_action <- mkEngine(toList(vec(step_1)));
    Control::NopAction nop_action <- mkEngine(toList(vec(step_1)));
    RoutingMatchTable _routing_table <- mkMatchTable_Routing("_routing");
    Control::RoutingTable _routing <- mkTable(table_request, table_execute, _routing_table);
    messageM(printType(typeOf(_routing_table)));
    messageM(printType(typeOf(_routing)));
    mkConnection(toClient(_routing_req_ff, _routing_rsp_ff), _routing.prev_control_state);
    mkConnection(_routing.next_control_state[0], nop_action.prev_control_state);
    mkConnection(_routing.next_control_state[1], forward_action.prev_control_state);
    mkConnection(_routing.next_control_state[2], noAction_action.prev_control_state);
    rule rl_entry if (entry_req_ff.notEmpty);
        entry_req_ff.deq;
        let _req = entry_req_ff.first;
        let meta = _req.meta;
        let pkt = _req.pkt;
        MetadataRequest req = MetadataRequest {pkt: pkt, meta: meta};
        .routing_req_ff.enq(req);
        dbprint(3, $format(".routing", fshow(meta)));
    endrule
    rule rl__routing if (_routing_rsp_ff.notEmpty);
        _routing_rsp_ff.deq;
        let _rsp = _routing_rsp_ff.first;
        let meta = _rsp.meta;
        let pkt = _rsp.pkt;
        case (_rsp) matches
            default: begin
                MetadataRequest req = MetadataRequest { pkt : pkt, meta : meta};
                _req_ff.enq(req);
                dbprint(3, $format("default ", fshow(meta)));
            end
        endcase
    endrule
    interface prev = toPipeIn(entry_req_ff);
    interface next = toPipeOut(exit_req_ff);
    method _routing_add_entry = _routing.add_entry;
    method Action set_verbosity (int verbosity);
        cf_verbosity <= verbosity;
        _routing.set_verbosity(verbosity);
    endmethod
endmodule
// =============== control egress ==============
interface Egress;
    interface PipeIn#(MetadataRequest) prev;
    interface PipeOut#(MetadataRequest) next;
    method Action set_verbosity(int verbosity);
endinterface
module mkEgress (Egress);
    `PRINT_DEBUG_MSG
    FIFOF#(MetadataRequest) entry_req_ff <- mkFIFOF;
    FIFOF#(MetadataRequest) entry_rsp_ff <- mkFIFOF;
    FIFOF#(MetadataRequest) exit_req_ff <- mkFIFOF;
    FIFOF#(MetadataRequest) exit_rsp_ff <- mkFIFOF;
    rule rl_entry if (entry_req_ff.notEmpty);
        entry_req_ff.deq;
        let _req = entry_req_ff.first;
        let meta = _req.meta;
        let pkt = _req.pkt;
        MetadataRequest req = MetadataRequest {pkt: pkt, meta: meta};
        exit_req_ff.enq(req);
        dbprint(3, $format("exit", fshow(meta)));
    endrule
    interface prev = toPipeIn(entry_req_ff);
    interface next = toPipeOut(exit_req_ff);
    method Action set_verbosity (int verbosity);
        cf_verbosity <= verbosity;
    endmethod
endmodule
