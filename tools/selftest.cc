// build.sh self-test (C++): the order in which a template's body instantiates other templates (the
// original's build compiler evaluated call arguments right to left), virtual functions, a vtable, and an
// exception thrown and caught. It defines a global function first, so the EH symbol names are not random.
extern "C" int ext(int);

int first_global(int x) { return ext(x) + 1; }

template <int N> int val() { return N + ext(N); }
template <class T> int order(T t)           // instantiated at the end: the order of val<>s is the test
{
    return val<sizeof(T)>() + val<sizeof(T) + 1>() * val<sizeof(T) + 2>() + (int) t;
}

struct Shape {
    int id;
    Shape(int i) : id(i) {}
    virtual ~Shape() { ext(id); }
    virtual int area() const = 0;
};
struct Rect : Shape {
    int w, h;
    Rect(int a, int b) : Shape(1), w(a), h(b) {}
    int area() const { return w * h; }
};
struct Fail { int code; Fail(int c) : code(c) {} };

int measure(const Shape &s) {
    if (s.area() < 0) throw Fail(s.id);
    return s.area();
}
int guarded(int a, int b) {
    try {
        Rect r(a, b);
        return measure(r) + order(a) + order('c');
    } catch (Fail &f) {
        return -f.code;
    }
}
