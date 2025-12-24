#include "ImagoApp.h"

int main(int, char**)
{
    ImagoApp app;
    if (app.Init()) {
        app.Run();
    }
    return 0;
}
