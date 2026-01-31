#include <iostream>
#include <unordered_map>
#ifdef __cplusplus
extern "C" {
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
typedef uint64_t ForwardReqT;
typedef uint64_t ForwardRspT;
std::unordered_map<ForwardReqT, ForwardRspT> tbl__forward;
extern "C" ForwardReqT matchtable_read__forward(ForwardReqT rdata) {
    auto it = tbl__forward.find(rdata);
    if (it != tbl__forward.end()) {
        return tbl__forward[rdata];
    } else {
        return 0;
    }
}
extern "C" void matchtable_write__forward(ForwardReqT wdata, ForwardRspT action){
    tbl__forward[wdata] = action;
}
typedef uint64_t Ipv4LpmReqT;
typedef uint64_t Ipv4LpmRspT;
std::unordered_map<Ipv4LpmReqT, Ipv4LpmRspT> tbl__ipv4_lpm;
extern "C" Ipv4LpmReqT matchtable_read__ipv4_lpm(Ipv4LpmReqT rdata) {
    auto it = tbl__ipv4_lpm.find(rdata);
    if (it != tbl__ipv4_lpm.end()) {
        return tbl__ipv4_lpm[rdata];
    } else {
        return 0;
    }
}
extern "C" void matchtable_write__ipv4_lpm(Ipv4LpmReqT wdata, Ipv4LpmRspT action){
    tbl__ipv4_lpm[wdata] = action;
}
#ifdef __cplusplus
}
#endif
#include <iostream>
#include <unordered_map>
#ifdef __cplusplus
extern "C" {
#endif
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
typedef uint64_t SendFrameReqT;
typedef uint64_t SendFrameRspT;
std::unordered_map<SendFrameReqT, SendFrameRspT> tbl__send_frame;
extern "C" SendFrameReqT matchtable_read__send_frame(SendFrameReqT rdata) {
    auto it = tbl__send_frame.find(rdata);
    if (it != tbl__send_frame.end()) {
        return tbl__send_frame[rdata];
    } else {
        return 0;
    }
}
extern "C" void matchtable_write__send_frame(SendFrameReqT wdata, SendFrameRspT action){
    tbl__send_frame[wdata] = action;
}
#ifdef __cplusplus
}
#endif
