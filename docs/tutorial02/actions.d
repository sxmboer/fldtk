import fl;
import std.format : format;

void sayHello()
{
    message("Hello from actions.d!");
}

int clicks;

void countClick(Button button)
{
    clicks++;
    button.label(format("Clicks: %d", clicks));
}
