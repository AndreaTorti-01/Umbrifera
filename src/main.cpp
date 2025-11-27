#include "UmbriferaApp.h"

int main(int, char**)
{
    UmbriferaApp app;
    if (app.Init()) {
        app.Run();
    }
    return 0;
}
