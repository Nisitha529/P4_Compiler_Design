/* 
<P4Program>(126823)
  <Type_Error>(17)
  <Type_Extern>(89)
  <Type_Extern>(110)
  <Method>(125)
  <Declaration_MatchKind>(150)
  <Declaration_MatchKind>(156)
  <Type_Struct>(122174)
  <Type_Extern>(339)
  <Type_Enum>(347)
  <Type_Enum>(353)
  <Type_Extern>(384)
  <Type_Extern>(410)
  <Type_Extern>(448)
  <Type_Extern>(480)
  <Type_Extern>(529)
  <Type_Extern>(547)
  <Type_Enum>(592)
  <Method>(601)
  <Type_Extern>(652)
  <Type_Parser>(756)
  <Type_Control>(773)
  <Type_Control>(799)
  <Type_Control>(825)
  <Type_Control>(842)
  <Type_Control>(864)
  <Type_Package>(927)
  <Type_Struct>(1187)
  <Type_Header>(983)
  <Type_Header>(1077)
  <Type_Struct>(122639)
  <Type_Struct>(122649)
  <P4Parser>(122667)
  <P4Control>(122756)
  <P4Control>(122885)
  <P4Control>(123140)
  <Type_Struct>(107419)
  <P4Control>(127946)
  <P4Control>(128036)
  <Declaration_Instance>(123365) */
/* 
  <Type_Error>(17) */
#include <core.p4>
#include <v1model.p4>

/* 
  <Type_Struct>(1187) */
struct routing_metadata_t {
/* 
    <StructField>(1179)
      <Annotations>(2)
      <Type_Bits>(0) */
        bit<32> nhop_ipv4;
}

/* 
  <Type_Header>(983) */
header ethernet_t {
/* 
    <StructField>(956)
      <Annotations>(2)
      <Type_Bits>(257) */
        bit<48> dstAddr;
/* 
    <StructField>(962)
      <Annotations>(2)
      <Type_Bits>(257) */
        bit<48> srcAddr;
/* 
    <StructField>(968)
      <Annotations>(2)
      <Type_Bits>(192) */
        bit<16> etherType;
}

/* 
  <Type_Header>(1077) */
header ipv4_t {
/* 
    <StructField>(994)
      <Annotations>(2)
      <Type_Bits>(993) */
        bit<4>  version;
/* 
    <StructField>(1000)
      <Annotations>(2)
      <Type_Bits>(993) */
        bit<4>  ihl;
/* 
    <StructField>(1006)
      <Annotations>(2)
      <Type_Bits>(939) */
        bit<8>  diffserv;
/* 
    <StructField>(1012)
      <Annotations>(2)
      <Type_Bits>(192) */
        bit<16> totalLen;
/* 
    <StructField>(1018)
      <Annotations>(2)
      <Type_Bits>(192) */
        bit<16> identification;
/* 
    <StructField>(1025)
      <Annotations>(2)
      <Type_Bits>(1024) */
        bit<3>  flags;
/* 
    <StructField>(1032)
      <Annotations>(2)
      <Type_Bits>(1031) */
        bit<13> fragOffset;
/* 
    <StructField>(1038)
      <Annotations>(2)
      <Type_Bits>(939) */
        bit<8>  ttl;
/* 
    <StructField>(1044)
      <Annotations>(2)
      <Type_Bits>(939) */
        bit<8>  protocol;
/* 
    <StructField>(1050)
      <Annotations>(2)
      <Type_Bits>(192) */
        bit<16> hdrChecksum;
/* 
    <StructField>(1056)
      <Annotations>(2)
      <Type_Bits>(0) */
        bit<32> srcAddr;
/* 
    <StructField>(1062)
      <Annotations>(2)
      <Type_Bits>(0) */
        bit<32> dstAddr;
}

/* 
  <Type_Struct>(122639) */
struct metadata {
/* 
    <StructField>(122641)
      <Annotations>(122642)
      <Type_Name>(3527) */
        @name("routing_metadata") 
    routing_metadata_t routing_metadata;
}

/* 
  <Type_Struct>(122649) */
struct headers {
/* 
    <StructField>(122651)
      <Annotations>(122652)
      <Type_Name>(3538) */
        @name("ethernet") 
    ethernet_t ethernet;
/* 
    <StructField>(122659)
      <Annotations>(122660)
      <Type_Name>(3547) */
        @name("ipv4") 
    ipv4_t     ipv4;
}

/* 
  <P4Parser>(122667) */
/* 
    <Type_Parser>(3577)
      <Annotations>(2)
      <TypeParameters>(3575)
      <ParameterList>(3555) */
parser ParserImpl(/* 
        <Parameter>(3559)
          <Annotations>(2)
          <Type_Name>(3558) */
packet_in packet, /* 
        <Parameter>(3562)
          <Annotations>(2)
          <Type_Name>(3561) */
out headers hdr, /* 
        <Parameter>(3567)
          <Annotations>(2)
          <Type_Name>(3566) */
inout metadata meta, /* 
        <Parameter>(3572)
          <Annotations>(2)
          <Type_Name>(3571) */
inout standard_metadata_t standard_metadata) {
    /* 
    <ParserState>(122689) */
    @name(".parse_ethernet") state parse_ethernet {
        /* 
      <MethodCallStatement>(122696)
        <MethodCallExpression>(122697)
          <Member>(122698)extract
            <PathExpression>(122699)
              packet
          <Vector<Type>>(17263), size=1
            <Type_Name>(17264)
              ethernet_t
          <Vector<Expression>>(122704), size=1
            <Member>(122705)ethernet
              <PathExpression>(122706)
                hdr */
        packet.extract<ethernet_t>(hdr.ethernet);
/* 
      <SelectExpression>(122708)
        <ListExpression>(122710)
          <Member>(122712)etherType
            <Member>(122713)ethernet
              <PathExpression>(122714)
                hdr
        <SelectCase>(122715)
          <Constant>(3630) 2048
            <Type_Bits>(192)
          <PathExpression>(122717)
            parse_ipv4
        <SelectCase>(122719)
          <DefaultExpression>(122720)
          <PathExpression>(122721)
            accept */
                transition select(hdr.ethernet.etherType) {
            /* 
        <SelectCase>(122715)
          <Constant>(3630) 2048
            <Type_Bits>(192)
          <PathExpression>(122717)
            parse_ipv4 */
            16w0x800: parse_ipv4;
            /* 
        <SelectCase>(122719)
          <DefaultExpression>(122720)
          <PathExpression>(122721)
            accept */
            default: accept;
        }
    }
    /* 
    <ParserState>(122723) */
    @name(".parse_ipv4") state parse_ipv4 {
        /* 
      <MethodCallStatement>(122730)
        <MethodCallExpression>(122731)
          <Member>(122732)extract
            <PathExpression>(122733)
              packet
          <Vector<Type>>(17297), size=1
            <Type_Name>(17298)
              ipv4_t
          <Vector<Expression>>(122738), size=1
            <Member>(122739)ipv4
              <PathExpression>(122740)
                hdr */
        packet.extract<ipv4_t>(hdr.ipv4);
/* 
      <PathExpression>(122741)
        accept */
                transition accept;
    }
    /* 
    <ParserState>(122743) */
    @name(".start") state start {
/* 
      <PathExpression>(122750)
        parse_ethernet */
                transition parse_ethernet;
    }
}

/* 
  <P4Control>(122756) */
/* 
    <Type_Control>(3761)
      <Annotations>(2)
      <TypeParameters>(3759)
      <ParameterList>(3742) */
control egress(/* 
        <Parameter>(3746)
          <Annotations>(2)
          <Type_Name>(3745) */
inout headers hdr, /* 
        <Parameter>(3751)
          <Annotations>(2)
          <Type_Name>(3750) */
inout metadata meta, /* 
        <Parameter>(3756)
          <Annotations>(2)
          <Type_Name>(3755) */
inout standard_metadata_t standard_metadata) {
    /* 
    <P4Action>(122774)
      <Annotations>(122775)
      <ParameterList>(142)
      <BlockStatement>(49979) */
    @name("NoAction") action NoAction_0() /* 
      <BlockStatement>(49979) */
    {
    }
    /* 
    <P4Action>(122784)
      <Annotations>(122785)
      <ParameterList>(78547)
      <BlockStatement>(122793) */
    @name(".rewrite_mac") action rewrite_mac_0(/* 
        <Parameter>(78553)
          <Annotations>(2)
          <Type_Bits>(257) */
bit<48> smac) /* 
      <BlockStatement>(122793) */
    {
        /* 
        <AssignmentStatement>(122795)
          <Member>(122796)srcAddr
            <Member>(122797)ethernet
              <PathExpression>(122798)
                hdr
          <PathExpression>(122800)
            smac */
        hdr.ethernet.srcAddr = smac;
    }
    /* 
    <P4Action>(122802)
      <Annotations>(122803)
      <ParameterList>(3797)
      <BlockStatement>(122810) */
    @name("._drop3") action _drop3_0() /* 
      <BlockStatement>(122810) */
    {
        /* 
        <MethodCallStatement>(122812)
          <MethodCallExpression>(122813)
            <PathExpression>(122814)
              mark_to_drop
            <Vector<Type>>(3802), size=0
            <Vector<Expression>>(43297), size=0 */
        mark_to_drop();
    }
    /* 
    <P4Table>(122818)
      <Annotations>(122819)
      <TableProperties>(122824) */
    @name(".send_frame") table send_frame {
        /* 
        <Property>(122826) */
        actions = /* 
          <ActionList>(122827)
            <ActionListElement>(122829)
            <ActionListElement>(122835)
            <ActionListElement>(122841) */
        {
            /* 
            <ActionListElement>(122829)
              <Annotations>(2)
              <MethodCallExpression>(122830)
                <PathExpression>(122831)
                  rewrite_mac_0/rewrite_mac
                <Vector<Type>>(6738), size=0
                <Vector<Expression>>(90287), size=0 */
            rewrite_mac_0();
            /* 
            <ActionListElement>(122835)
              <Annotations>(2)
              <MethodCallExpression>(122836)
                <PathExpression>(122837)
                  _drop3_0/_drop3
                <Vector<Type>>(6744), size=0
                <Vector<Expression>>(90305), size=0 */
            _drop3_0();
            /* 
            <ActionListElement>(122841)
              <Annotations>(6750)
                <Annotation>(6747)
              <MethodCallExpression>(122846)
                <PathExpression>(122847)
                  NoAction_0/NoAction_2
                <Vector<Type>>(6754), size=0
                <Vector<Expression>>(90327), size=0 */
            @defaultonly NoAction_0();
        }
        /* 
        <Property>(122851) */
        key = /* 
          <Key>(122852)
            <KeyElement>(122854) */
        {
/* 
              <KeyElement>(122854)
                <Annotations>(122855)
                <Member>(122860)egress_port
                  <PathExpression>(122861)
                    standard_metadata
                <PathExpression>(122863)
                  exact */
                        standard_metadata.egress_port: exact @name("standard_metadata.egress_port") ;
        }
        /* 
        <Property>(122865) */
        size = /* 
          <ExpressionValue>(122866)
            <Constant>(122867) 256
              <Type_InfInt>(110671) */
        256;
        /* 
        <Property>(122869) */
        default_action = /* 
          <ExpressionValue>(122870)
            <MethodCallExpression>(122871)
              <PathExpression>(122872)
                NoAction_0/NoAction_2
              <Vector<Type>>(6775), size=0
              <Vector<Expression>>(6773), size=0 */
        NoAction_0();
    }
    apply /* 
    <BlockStatement>(122876) */
    {
        /* 
      <MethodCallStatement>(122878)
        <MethodCallExpression>(122879)
          <Member>(122880)apply
            <PathExpression>(122881)
              send_frame
          <Vector<Type>>(3871), size=0
          <Vector<Expression>>(43400), size=0 */
        send_frame.apply();
    }
}

/* 
  <P4Control>(122885) */
/* 
    <Type_Control>(3899)
      <Annotations>(2)
      <TypeParameters>(3897)
      <ParameterList>(3880) */
control ingress(/* 
        <Parameter>(3884)
          <Annotations>(2)
          <Type_Name>(3883) */
inout headers hdr, /* 
        <Parameter>(3889)
          <Annotations>(2)
          <Type_Name>(3888) */
inout metadata meta, /* 
        <Parameter>(3894)
          <Annotations>(2)
          <Type_Name>(3893) */
inout standard_metadata_t standard_metadata) {
    /* 
    <P4Action>(122903)
      <Annotations>(122775)
      <ParameterList>(142)
      <BlockStatement>(49979) */
    @name("NoAction") action NoAction_1() /* 
      <BlockStatement>(49979) */
    {
    }
    /* 
    <P4Action>(122904)
      <Annotations>(122775)
      <ParameterList>(142)
      <BlockStatement>(49979) */
    @name("NoAction") action NoAction_5() /* 
      <BlockStatement>(49979) */
    {
    }
    /* 
    <P4Action>(122905)
      <Annotations>(122906)
      <ParameterList>(78595)
      <BlockStatement>(122914) */
    @name(".set_dmac") action set_dmac_0(/* 
        <Parameter>(78601)
          <Annotations>(2)
          <Type_Bits>(257) */
bit<48> dmac) /* 
      <BlockStatement>(122914) */
    {
        /* 
        <AssignmentStatement>(122916)
          <Member>(122917)dstAddr
            <Member>(122918)ethernet
              <PathExpression>(122919)
                hdr
          <PathExpression>(122921)
            dmac */
        hdr.ethernet.dstAddr = dmac;
    }
    /* 
    <P4Action>(122923)
      <Annotations>(122924)
      <ParameterList>(3935)
      <BlockStatement>(122931) */
    @name("._drop2") action _drop2_0() /* 
      <BlockStatement>(122931) */
    {
        /* 
        <MethodCallStatement>(122933)
          <MethodCallExpression>(122934)
            <PathExpression>(122935)
              mark_to_drop
            <Vector<Type>>(3940), size=0
            <Vector<Expression>>(43496), size=0 */
        mark_to_drop();
    }
    /* 
    <P4Action>(122939)
      <Annotations>(122940)
      <ParameterList>(78669)
      <BlockStatement>(122949) */
    @name(".set_nhop") action set_nhop_0(/* 
        <Parameter>(78675)
          <Annotations>(2)
          <Type_Bits>(0) */
bit<32> nhop_ipv4, /* 
        <Parameter>(78680)
          <Annotations>(2)
          <Type_Bits>(172) */
    bit<9> _port) /* 
      <BlockStatement>(122949) */
    {
        /* 
        <AssignmentStatement>(122951)
          <Member>(122952)nhop_ipv4
            <Member>(122953)routing_metadata
              <PathExpression>(122954)
                meta
          <PathExpression>(122956)
            nhop_ipv4 */
        meta.routing_metadata.nhop_ipv4 = nhop_ipv4;
        /* 
        <AssignmentStatement>(122958)
          <Member>(122959)egress_port
            <PathExpression>(122960)
              standard_metadata
          <PathExpression>(122962)
            _port */
        standard_metadata.egress_port = _port;
        /* 
        <AssignmentStatement>(122964)
          <Member>(122965)ttl
            <Member>(122966)ipv4
              <PathExpression>(122967)
                hdr
          <Add>(122969)
            <Member>(122970)ttl
              <Member>(122971)ipv4
                <PathExpression>(122972)
                  hdr
            <Constant>(29301) 255
              <Type_Bits>(939) */
        hdr.ipv4.ttl = hdr.ipv4.ttl + 8w255;
    }
    /* 
    <P4Action>(122975)
      <Annotations>(122976)
      <ParameterList>(4068)
      <BlockStatement>(122983) */
    @name("._drop1") action _drop1_0() /* 
      <BlockStatement>(122983) */
    {
        /* 
        <MethodCallStatement>(122985)
          <MethodCallExpression>(122986)
            <PathExpression>(122987)
              mark_to_drop
            <Vector<Type>>(4073), size=0
            <Vector<Expression>>(43584), size=0 */
        mark_to_drop();
    }
    /* 
    <P4Table>(122991)
      <Annotations>(122992)
      <TableProperties>(122997) */
    @name(".forward") table forward {
        /* 
        <Property>(122999) */
        actions = /* 
          <ActionList>(123000)
            <ActionListElement>(123002)
            <ActionListElement>(123008)
            <ActionListElement>(123014) */
        {
            /* 
            <ActionListElement>(123002)
              <Annotations>(2)
              <MethodCallExpression>(123003)
                <PathExpression>(123004)
                  set_dmac_0/set_dmac
                <Vector<Type>>(6903), size=0
                <Vector<Expression>>(90520), size=0 */
            set_dmac_0();
            /* 
            <ActionListElement>(123008)
              <Annotations>(2)
              <MethodCallExpression>(123009)
                <PathExpression>(123010)
                  _drop2_0/_drop2
                <Vector<Type>>(6909), size=0
                <Vector<Expression>>(90538), size=0 */
            _drop2_0();
            /* 
            <ActionListElement>(123014)
              <Annotations>(6915)
                <Annotation>(6912)
              <MethodCallExpression>(123019)
                <PathExpression>(123020)
                  NoAction_1/NoAction_3
                <Vector<Type>>(6919), size=0
                <Vector<Expression>>(90560), size=0 */
            @defaultonly NoAction_1();
        }
        /* 
        <Property>(123024) */
        key = /* 
          <Key>(123025)
            <KeyElement>(123027) */
        {
/* 
              <KeyElement>(123027)
                <Annotations>(123028)
                <Member>(123033)nhop_ipv4
                  <Member>(123034)routing_metadata
                    <PathExpression>(123035)
                      meta
                <PathExpression>(123037)
                  exact */
                        meta.routing_metadata.nhop_ipv4: exact @name("meta.routing_metadata.nhop_ipv4") ;
        }
        /* 
        <Property>(123039) */
        size = /* 
          <ExpressionValue>(123040)
            <Constant>(123041) 512
              <Type_InfInt>(111188) */
        512;
        /* 
        <Property>(123043) */
        default_action = /* 
          <ExpressionValue>(123044)
            <MethodCallExpression>(123045)
              <PathExpression>(123046)
                NoAction_1/NoAction_3
              <Vector<Type>>(6940), size=0
              <Vector<Expression>>(6938), size=0 */
        NoAction_1();
    }
    /* 
    <P4Table>(123050)
      <Annotations>(123051)
      <TableProperties>(123056) */
    @name(".ipv4_lpm") table ipv4_lpm {
        /* 
        <Property>(123058) */
        actions = /* 
          <ActionList>(123059)
            <ActionListElement>(123061)
            <ActionListElement>(123067)
            <ActionListElement>(123073) */
        {
            /* 
            <ActionListElement>(123061)
              <Annotations>(2)
              <MethodCallExpression>(123062)
                <PathExpression>(123063)
                  set_nhop_0/set_nhop
                <Vector<Type>>(6957), size=0
                <Vector<Expression>>(90615), size=0 */
            set_nhop_0();
            /* 
            <ActionListElement>(123067)
              <Annotations>(2)
              <MethodCallExpression>(123068)
                <PathExpression>(123069)
                  _drop1_0/_drop1
                <Vector<Type>>(6963), size=0
                <Vector<Expression>>(90633), size=0 */
            _drop1_0();
            /* 
            <ActionListElement>(123073)
              <Annotations>(6969)
                <Annotation>(6966)
              <MethodCallExpression>(123078)
                <PathExpression>(123079)
                  NoAction_5/NoAction_4
                <Vector<Type>>(6973), size=0
                <Vector<Expression>>(90655), size=0 */
            @defaultonly NoAction_5();
        }
        /* 
        <Property>(123083) */
        key = /* 
          <Key>(123084)
            <KeyElement>(123086) */
        {
/* 
              <KeyElement>(123086)
                <Annotations>(123087)
                <Member>(123092)dstAddr
                  <Member>(123093)ipv4
                    <PathExpression>(123094)
                      hdr
                <PathExpression>(123096)
                  exact */
                        hdr.ipv4.dstAddr: exact @name("hdr.ipv4.dstAddr") ;
        }
        /* 
        <Property>(123098) */
        size = /* 
          <ExpressionValue>(123099)
            <Constant>(123100) 1024
              <Type_InfInt>(111295) */
        1024;
        /* 
        <Property>(123102) */
        default_action = /* 
          <ExpressionValue>(123103)
            <MethodCallExpression>(123104)
              <PathExpression>(123105)
                NoAction_5/NoAction_4
              <Vector<Type>>(6994), size=0
              <Vector<Expression>>(6992), size=0 */
        NoAction_5();
    }
    apply /* 
    <BlockStatement>(123109) */
    {
        /* 
      <IfStatement>(123111) */
        if (hdr.ipv4.isValid() && hdr.ipv4.ttl > 8w0) /* 
        <BlockStatement>(123124) */
        {
            /* 
          <MethodCallStatement>(123126)
            <MethodCallExpression>(123127)
              <Member>(123128)apply
                <PathExpression>(123129)
                  ipv4_lpm
              <Vector<Type>>(4239), size=0
              <Vector<Expression>>(43760), size=0 */
            ipv4_lpm.apply();
            /* 
          <MethodCallStatement>(123133)
            <MethodCallExpression>(123134)
              <Member>(123135)apply
                <PathExpression>(123136)
                  forward
              <Vector<Type>>(4249), size=0
              <Vector<Expression>>(43826), size=0 */
            forward.apply();
        }
    }
}

/* 
  <P4Control>(123140) */
/* 
    <Type_Control>(4279)
      <Annotations>(2)
      <TypeParameters>(4280)
      <ParameterList>(4272) */
control DeparserImpl(/* 
        <Parameter>(4276)
          <Annotations>(2)
          <Type_Name>(4275) */
packet_out packet, /* 
        <Parameter>(4265)
          <Annotations>(2)
          <Type_Name>(4264) */
in headers hdr) {
    apply /* 
    <BlockStatement>(123155) */
    {
        /* 
      <MethodCallStatement>(123157)
        <MethodCallExpression>(123158)
          <Member>(123159)emit
            <PathExpression>(123160)
              packet
          <Vector<Type>>(17695), size=1
            <Type_Name>(17696)
              ethernet_t
          <Vector<Expression>>(123165), size=1
            <Member>(123166)ethernet
              <PathExpression>(123167)
                hdr */
        packet.emit<ethernet_t>(hdr.ethernet);
        /* 
      <MethodCallStatement>(123169)
        <MethodCallExpression>(123170)
          <Member>(123171)emit
            <PathExpression>(123172)
              packet
          <Vector<Type>>(17706), size=1
            <Type_Name>(17707)
              ipv4_t
          <Vector<Expression>>(123177), size=1
            <Member>(123178)ipv4
              <PathExpression>(123167)
                hdr */
        packet.emit<ipv4_t>(hdr.ipv4);
    }
}

/* 
  <Type_Struct>(107419) */
struct tuple_0 {
/* 
    <StructField>(107406)
      <Annotations>(2)
      <Type_Bits>(993) */
        bit<4>  field;
/* 
    <StructField>(107407)
      <Annotations>(2)
      <Type_Bits>(993) */
        bit<4>  field_0;
/* 
    <StructField>(107408)
      <Annotations>(2)
      <Type_Bits>(939) */
        bit<8>  field_1;
/* 
    <StructField>(107409)
      <Annotations>(2)
      <Type_Bits>(192) */
        bit<16> field_2;
/* 
    <StructField>(107410)
      <Annotations>(2)
      <Type_Bits>(192) */
        bit<16> field_3;
/* 
    <StructField>(107411)
      <Annotations>(2)
      <Type_Bits>(1024) */
        bit<3>  field_4;
/* 
    <StructField>(107412)
      <Annotations>(2)
      <Type_Bits>(1031) */
        bit<13> field_5;
/* 
    <StructField>(107413)
      <Annotations>(2)
      <Type_Bits>(939) */
        bit<8>  field_6;
/* 
    <StructField>(107414)
      <Annotations>(2)
      <Type_Bits>(939) */
        bit<8>  field_7;
/* 
    <StructField>(107415)
      <Annotations>(2)
      <Type_Bits>(0) */
        bit<32> field_8;
/* 
    <StructField>(107416)
      <Annotations>(2)
      <Type_Bits>(0) */
        bit<32> field_9;
}

/* 
  <P4Control>(127946) */
/* 
    <Type_Control>(4314)
      <Annotations>(2)
      <TypeParameters>(4315)
      <ParameterList>(4302) */
control verifyChecksum(/* 
        <Parameter>(4306)
          <Annotations>(2)
          <Type_Name>(4305) */
in headers hdr, /* 
        <Parameter>(4311)
          <Annotations>(2)
          <Type_Name>(4310) */
inout metadata meta) {
    /* 
    <Declaration_Variable>(127962) */
    bit<16> tmp_2;
    /* 
    <Declaration_Instance>(123209)
      <Annotations>(123211)
        <Annotation>(123213)
      <Type_Name>(4319)
        Checksum16
      <Vector<Expression>>(4320), size=0 */
    @name("ipv4_checksum") Checksum16() ipv4_checksum;
    apply /* 
    <BlockStatement>(125119) */
    {
        /* 
      <AssignmentStatement>(123221)
        <PathExpression>(123222)
          tmp_2
        <MethodCallExpression>(123224)
          <Member>(123225)get
            <PathExpression>(123226)
              ipv4_checksum
          <Vector<Type>>(107402), size=1
            <Type_Name>(107421)
          <Vector<Expression>>(123231), size=1
            <ListExpression>(123232)
              <Member>(123234)version
                <Member>(123235)ipv4
                  <PathExpression>(123236)
                    hdr
              <Member>(123238)ihl
                <Member>(123239)ipv4
                  <PathExpression>(123240)
                    hdr
              <Member>(123241)diffserv
                <Member>(123242)ipv4
                  <PathExpression>(123243)
                    hdr
              <Member>(123244)totalLen
                <Member>(123245)ipv4
                  <PathExpression>(123246)
                    hdr
              <Member>(123247)identification
                <Member>(123248)ipv4
                  <PathExpression>(123249)
                    hdr
              <Member>(123250)flags
                <Member>(123251)ipv4
                  <PathExpression>(123252)
                    hdr
              <Member>(123253)fragOffset
                <Member>(123254)ipv4
                  <PathExpression>(123255)
                    hdr
              <Member>(123256)ttl
                <Member>(123257)ipv4
                  <PathExpression>(123258)
                    hdr
              <Member>(123259)protocol
                <Member>(123260)ipv4
                  <PathExpression>(123261)
                    hdr
              <Member>(123262)srcAddr
                <Member>(123263)ipv4
                  <PathExpression>(123264)
                    hdr
              <Member>(123265)dstAddr
                <Member>(123266)ipv4
                  <PathExpression>(123267)
                    hdr */
        tmp_2 = ipv4_checksum.get<tuple_0>({ hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.diffserv, hdr.ipv4.totalLen, hdr.ipv4.identification, hdr.ipv4.flags, hdr.ipv4.fragOffset, hdr.ipv4.ttl, hdr.ipv4.protocol, hdr.ipv4.srcAddr, hdr.ipv4.dstAddr });
        /* 
      <IfStatement>(125094) */
        if (hdr.ipv4.hdrChecksum == tmp_2) 
            /* 
        <MethodCallStatement>(123280)
          <MethodCallExpression>(123281)
            <PathExpression>(123282)
              mark_to_drop
            <Vector<Type>>(4438), size=0
            <Vector<Expression>>(44177), size=0 */
            mark_to_drop();
    }
}

/* 
  <P4Control>(128036) */
/* 
    <Type_Control>(4459)
      <Annotations>(2)
      <TypeParameters>(4460)
      <ParameterList>(4447) */
control computeChecksum(/* 
        <Parameter>(4451)
          <Annotations>(2)
          <Type_Name>(4450) */
inout headers hdr, /* 
        <Parameter>(4456)
          <Annotations>(2)
          <Type_Name>(4455) */
inout metadata meta) {
    /* 
    <Declaration_Variable>(128052) */
    bit<16> tmp_4;
    /* 
    <Declaration_Instance>(123302)
      <Annotations>(123304)
        <Annotation>(123306)
      <Type_Name>(4466)
        Checksum16
      <Vector<Expression>>(4467), size=0 */
    @name("ipv4_checksum") Checksum16() ipv4_checksum_2;
    apply /* 
    <BlockStatement>(123312) */
    {
        /* 
      <AssignmentStatement>(123314)
        <PathExpression>(123315)
          tmp_4
        <MethodCallExpression>(123317)
          <Member>(123318)get
            <PathExpression>(123319)
              ipv4_checksum_2/ipv4_checksum
          <Vector<Type>>(107514), size=1
            <Type_Name>(107421)
          <Vector<Expression>>(123322), size=1
            <ListExpression>(123323)
              <Member>(123325)version
                <Member>(123326)ipv4
                  <PathExpression>(123327)
                    hdr
              <Member>(123329)ihl
                <Member>(123330)ipv4
                  <PathExpression>(123331)
                    hdr
              <Member>(123332)diffserv
                <Member>(123333)ipv4
                  <PathExpression>(123334)
                    hdr
              <Member>(123335)totalLen
                <Member>(123336)ipv4
                  <PathExpression>(123337)
                    hdr
              <Member>(123338)identification
                <Member>(123339)ipv4
                  <PathExpression>(123340)
                    hdr
              <Member>(123341)flags
                <Member>(123342)ipv4
                  <PathExpression>(123343)
                    hdr
              <Member>(123344)fragOffset
                <Member>(123345)ipv4
                  <PathExpression>(123346)
                    hdr
              <Member>(123347)ttl
                <Member>(123348)ipv4
                  <PathExpression>(123349)
                    hdr
              <Member>(123350)protocol
                <Member>(123351)ipv4
                  <PathExpression>(123352)
                    hdr
              <Member>(123353)srcAddr
                <Member>(123354)ipv4
                  <PathExpression>(123355)
                    hdr
              <Member>(123356)dstAddr
                <Member>(123357)ipv4
                  <PathExpression>(123358)
                    hdr */
        tmp_4 = ipv4_checksum_2.get<tuple_0>({ hdr.ipv4.version, hdr.ipv4.ihl, hdr.ipv4.diffserv, hdr.ipv4.totalLen, hdr.ipv4.identification, hdr.ipv4.flags, hdr.ipv4.fragOffset, hdr.ipv4.ttl, hdr.ipv4.protocol, hdr.ipv4.srcAddr, hdr.ipv4.dstAddr });
        /* 
      <AssignmentStatement>(123359)
        <Member>(123360)hdrChecksum
          <Member>(123361)ipv4
            <PathExpression>(123362)
              hdr
        <PathExpression>(123363)
          tmp_4 */
        hdr.ipv4.hdrChecksum = tmp_4;
    }
}

/* 
  <Declaration_Instance>(123365)
    <Annotations>(2)
    <Type_Specialized>(17883)
      <Type_Name>(4586)
      <Vector<Type>>(17878), size=2
    <Vector<Expression>>(123375), size=6
      <ConstructorCallExpression>(123376)
        <Type_Name>(4590)
          ParserImpl
        <Vector<Expression>>(4588), size=0
      <ConstructorCallExpression>(123380)
        <Type_Name>(4593)
          verifyChecksum
        <Vector<Expression>>(4588), size=0
      <ConstructorCallExpression>(123383)
        <Type_Name>(4596)
          ingress
        <Vector<Expression>>(4588), size=0
      <ConstructorCallExpression>(123386)
        <Type_Name>(4599)
          egress
        <Vector<Expression>>(4588), size=0
      <ConstructorCallExpression>(123389)
        <Type_Name>(4602)
          computeChecksum
        <Vector<Expression>>(4588), size=0
      <ConstructorCallExpression>(123392)
        <Type_Name>(4605)
          DeparserImpl
        <Vector<Expression>>(4588), size=0 */
/* 
    <Type_Specialized>(138177)
      <Type_Name>(4586)
        V1Switch
      <Vector<Type>>(138176), size=2
        <Type_Name>(17879)
        <Type_Name>(17881) */
V1Switch<headers, metadata>(ParserImpl(), verifyChecksum(), ingress(), egress(), computeChecksum(), DeparserImpl()) main;
