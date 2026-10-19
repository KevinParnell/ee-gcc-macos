/* build.sh self-test: a jump table, a double constant split into a 64-bit word (the 32-bit `long' quirk),
   float data, small data, a 64-bit divide and a struct copy. */
struct s { int a[5]; };
int g; static short h = 3; float fv[] = { 0.1f, -1.75f }; double dv = 1.1;
extern int ext(int);
int sw(int x) { switch (x) { case 0: return ext(1); case 1: return 7; case 2: return ext(3) + h;
    case 3: return g; case 4: return 9; case 5: return ext(x); default: return -1; } }
long long bits(void) { union { double d; long long l; } u; u.d = 1.1; return u.l; }
long long dv64(long long a, long long b) { return a / b + g; }
void cp(struct s *d, const struct s *p) { *d = *p; }
