// llvm-mos C++ 测试：类、new/delete、printf
// 注意：裸机 C++ 的 main 需要 extern "C"（-nostdlib 下会被名字修饰）
#include <stdio.h>
#include <new>

class Printer
{
public:
    explicit Printer(int n) : count(n) {}
    void print(const char *s)
    {
        for (int i = 0; i < count; ++i)
            printf("%s", s);
    }

private:
    int count;
};

extern "C" int main()
{
    Printer p(3);
    p.print("Hello C++\n");
    int *buf = new int[4];
    for (int i = 0; i < 4; ++i)
        buf[i] = i + 1;
    delete[] buf;
    return 0;
}
