// divider_pkg.sv
package divider_pkg;
  typedef enum logic [3:0] {
    RESET          = 4'b0000,
    READ           = 4'b0001,
    CHECK          = 4'b0010,
    ERROR_ST       = 4'b0011,
    PREP_INPUT     = 4'b0100,
    INIT           = 4'b0101,
    SHIFT_COMPUTE  = 4'b0110,   // placeholder (not used in this minimal fix)
    DIVIDE_COMPUTE = 4'b0111,
    NORMALIZE      = 4'b1000,   // placeholder (not used in this minimal fix)
    PREP_OUTPUT    = 4'b1001,
    DONE           = 4'b1010,
    STATEX         = 4'b1111
  } state_struct;
endpackage