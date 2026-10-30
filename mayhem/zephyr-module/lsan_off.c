/* Leak detection is not what this fleet fuzzes for: ASan stays on, LSan is switched off at build time. */
__attribute__((visibility("default"))) int __lsan_is_turned_off(void)
{
	return 1;
}
