module parser_generated(
  input  logic clk,
  input  logic rst_n,
  input  logic valid_in,
  input  logic [15:0] ethernet_etherType,
  input  logic [3:0] ipv4_ihl,
  input  logic [4:0] ipv4_option_option,
  input  logic [15:0] meta__parser_metadata_remaining1,
  input  logic [15:0] mri_count,
  output logic extract_ethernet,
  output logic extract_ipv4,
  output logic extract_ipv4_option,
  output logic extract_mri,
  output logic extract_swtraces,
  output logic done
);

  typedef enum logic [2:0] {
    START,
    PARSE_IPV4,
    PARSE_IPV4_OPTION,
    PARSE_MRI,
    PARSE_SWTRACE,
    ACCEPT
  } state_t;

  state_t state, next_state;

  always_comb begin
    extract_mri = 0;
    extract_swtraces = 0;
    extract_ethernet = 0;
    extract_ipv4_option = 0;
    extract_ipv4 = 0;
    done = 0;
    next_state = state;

    case (state)

      START: begin
        extract_ethernet = 1;
        case (ethernet_etherType)
          16'h0800: next_state = PARSE_IPV4;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_IPV4: begin
        extract_ipv4 = 1;
        case (ipv4_ihl)
          4'h5: next_state = ACCEPT;
          default: next_state = PARSE_IPV4_OPTION;
        endcase
      end

      PARSE_IPV4_OPTION: begin
        extract_ipv4_option = 1;
        case (ipv4_option_option)
          5'h1F: next_state = PARSE_MRI;
          default: next_state = ACCEPT;
        endcase
      end

      PARSE_MRI: begin
        extract_mri = 1;
        case (mri_count)
          16'h0000: next_state = ACCEPT;
          default: next_state = PARSE_SWTRACE;
        endcase
      end

      PARSE_SWTRACE: begin
        extract_swtraces = 1;
        case (meta__parser_metadata_remaining1)
          16'h0000: next_state = ACCEPT;
          default: next_state = PARSE_SWTRACE;
        endcase
      end

      ACCEPT: begin
        done = 1;
        next_state = START;
      end

    endcase
  end

  always_ff @(posedge clk) begin
    if (!rst_n)
      state <= ACCEPT;
    else if (valid_in)
      state <= next_state;
  end

endmodule
