NR block diagram: https://drive.google.com/file/d/1j90D19xMYoPvntIMmEMO7JHbfjNIhxzR/view?usp=drive_link



### Links
https://discord.com/channels/1158816618760118404/1158819200601706516

Current project assignments:
https://gtvault.sharepoint.com/:x:/s/SiliconJackets/ER9rUdvcgPFLnKWKsFkWZlMBQQ7IjQ-E5OFrvEP0PrjQ2g?e=12n3xU

SharePoint
https://gtvault.sharepoint.com/sites/SiliconJackets

Divider 2 Workplan
[https://gtvault.sharepoint.com/:w:/s/SiliconJackets/ER6vVItrnhhDkGjCIdF_UFUBeg84OZwG1VbDTzsILWrnHQ?e=XOcJFm](https://gtvault.sharepoint.com/:w:/s/SiliconJackets/ER6vVItrnhhDkGjCIdF_UFUBeg84OZwG1VbDTzsILWrnHQ?e=XOcJFm)


### Learning Links

RISC V
https://five-embeddev.com/riscv-user-isa-manual/Priv-v1.12/m.html

https://drive.google.com/file/d/1uviu1nH-tScFfgrovvFCrj7Omv8tFtkp/view (page 69)

[gtvault.sharepoint.com/:b:/s/SiliconJackets/ETS5XE7YGclJvGvhd_CnpBkB4a1UOfz6EjViLXB3YsWbZQ?e=6liBHK](https://gtvault.sharepoint.com/sites/SiliconJackets/Shared%20Documents/Forms/AllItems.aspx?id=%2Fsites%2FSiliconJackets%2FShared%20Documents%2FDigital%20Design%20Subteam%2FResources%2Friscv%2Dspec%2Dv2%2E2%2Epdf&parent=%2Fsites%2FSiliconJackets%2FShared%20Documents%2FDigital%20Design%20Subteam%2FResources&p=true&ga=1) (page 36)


Division Algorithm
https://en.wikipedia.org/wiki/Division_algorithm
https://web.ece.ucsb.edu/~parhami/pres_folder/f31-book-arith-pres-pt4.pdf
https://gmplib.org/manual/Division-Algorithms#Division-Algorithms

https://gmplib.org/

Sample Implementation
https://github.com/MuhammadMajiid/RV64IMAC/blob/main/RTL/riscv_core_div_in.sv
https://hardwaredescriptions.com/conquer-the-divide/ (IMP)
https://projectf.io/posts/division-in-verilog/ (Slow Div)


### RISC - V Architecture

#### M Extension for Integer Multiplication and Division

Standard integer multiplication and division instruction extension, containing multiply or divide values held in 2 integer registers

![[Pasted image 20250827072449.png]]

- DIV : XLEN bits x XLEN bits **unsigned** integer division --> rs1 / rs2 --> round towards 0
- DIVU : XLEN bits x XLEN bits **signed** integer division --> rs1 / rs2 --> round towards 0

- REM : Remainder of corresponding  **unsigned**  division operation
	For REM, the sign of a nonzero result equals the sign of the dividend
- REMU : Remainder of corresponding  **unsigned**  division operation

For both signed and unsigned division, except in the case of overflow, it holds that
`dividend = divisor x quotient + remainder`

If both the quotient and remainder are required from the same division, the recommended code sequence is: 
DIVU rdq, rs1, rs2; 
REMU rdr, rs1, rs2 (rdq cannot be the same as rs1 or rs2).
(Microarchitectures can then fuse these into a single divide operation instead of performing two separate divides). [CHECK IMPLEMENTATION]

[CHECK IGNORE 64 BIT]
- DIVW and DIVUW are RV64 instructions that divide the lower 32 bits of rs1 by the lower 32 bits of rs2, treating them as signed and unsigned integers, placing the 32-bit quotient in rd, sign-extended to 64bits.
- REMW and REMUW are RV64 instructions that provide the corresponding signed and unsigned remainder operations. Both REMW and REMUW always sign-extend the 32-bit result to 64 bits, including on a divide by zero.

##### Division by 0 and Overflow
- Division by 0
	- Quotient of division by 0 has all bits set 
	- Remainder equals the dividend
- Signed division overflow occurs only when the most negative integer is divided by -1
	- Quotient is equal to the dividend
	- Remainder is 0
	- Unsigned division overflow cannot occur

![[Pasted image 20250827074003.png]]


### Division Algorithms

**What is a division algorithm?**

A **division algorithm** is an algorithm which, given two integers _N_ and _D_ (respectively the numerator and the denominator), computes their quotient and/or remainder, the result of [Euclidean division](https://en.wikipedia.org/wiki/Euclidean_division "Euclidean division") (a = bq + r, 0<=r<a). 
Some are applied by hand, while others are employed by digital circuit designs and software.


**2 categories of algorithms**

**Slow Division**
- Slow division algorithms produce one digit of the final quotient per iteration. 
- Examples of slow division include [restoring](https://en.wikipedia.org/wiki/Division_algorithm#Restoring_division), non-performing restoring, [non-restoring](https://en.wikipedia.org/wiki/Division_algorithm#Non-restoring_division), and [SRT](https://en.wikipedia.org/wiki/Division_algorithm#SRT_division) division.

**Fast Division** (What we need!!)
- Fast division methods start with a close approximation to the final quotient and produce twice as many digits of the final quotient on each iteration.
- [Newton–Raphson](https://en.wikipedia.org/wiki/Division_algorithm#Newton%E2%80%93Raphson_division) and [Goldschmidt](https://en.wikipedia.org/wiki/Division_algorithm#Goldschmidt_division) algorithms fall into this category.

Discussion will refer to the form N/D=(Q,R) (Numerator, Denominator, Quotient, Remainder)




#### Hardware Speed Up Options
  
It's a niche corner case, but if you're dividing by a constant you have some options to speed it up.

- If the divider is a power of 2, the division is just a shift right.
    
- If the number being divided is a small enough number of bits, you can maybe use a look up table in memory instead of doing the division.
    
- And finally, you can compute the reciprocal of the divider, and then do fixed point multiplication in order to get the correct result.





### RoadMap

- Understand the implications of each division type: Documentation with explanations
- Algorithm Flowchart 
- PseudoCode
- Software Implementation
- Test Software
- Notes for comparison
- Plan out RTL input output ports, connecting with the rest of the module
- RTL Block diagram
- Complete functionality: Detailed descriptions --> for the RTL Implementation
- Test Plan: Cases, Testbenches
- Write as we test --> Start RTL
