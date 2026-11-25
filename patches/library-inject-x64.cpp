// Patched 64-bit/32-bit aware library-inject.so (LD_AUDIT) for SLSsteam on SteamOS / Linux.
// Fixes upstream bug where /usr/lib32 was searched in an unordered_set on x86_64 builds,
// causing 64-bit Steam child processes (like kde-open for OAuth browser login) to fail with:
//   "error while loading shared libraries: /usr/lib32/libcurl.so.4: wrong ELF class: ELFCLASS32"
//
// Build (x86_64):
//   g++ library-inject-x64.cpp -O3 -m64 -fPIC -shared -std=c++20 -static-libstdc++ -static-libgcc -Wl,--exclude-libs,ALL -o library-inject.so

#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <elf.h>
#include <filesystem>
#include <fstream>
#include <link.h>
#include <string>
#include <unordered_set>
#include <vector>

static const std::unordered_set<std::string> LIBS =
{
	"libcurl.so",
	"libcurl.so.3",
	"libcurl.so.4",
	"libcurl.so.4.0.0",
	"libcurl.so.4.1.0",
	"libcurl.so.4.2.0",
	"libcurl.so.4.3.0",
	"libcurl.so.4.4.0",
	"libcurl.so.4.5.0",
	"libcurl.so.4.6.0",
	"libcurl.so.4.7.0",
	"libcurl.so.4.8.0",
};

#if defined(__x86_64__) || defined(__aarch64__) || defined(_M_X64)
static constexpr unsigned char EXPECTED_ELF_CLASS = ELFCLASS64;
static const std::vector<std::string> DIRS =
{
	"/usr/local/lib64",
	"/usr/lib64",
	"/usr/lib/x86_64-linux-gnu",
	"/usr/local/lib",
	"/usr/lib",
};
#else
static constexpr unsigned char EXPECTED_ELF_CLASS = ELFCLASS32;
static const std::vector<std::string> DIRS =
{
	"/usr/local/lib32",
	"/usr/lib32",
	"/usr/lib/i386-linux-gnu",
	"/usr/local/lib",
	"/usr/lib",
};
#endif

static bool matches_elf_class(const char *path)
{
	std::ifstream f(path, std::ios::binary);
	if (!f) return false;
	unsigned char hdr[5] = {};
	if (!f.read(reinterpret_cast<char*>(hdr), sizeof(hdr))) return false;
	return hdr[0] == ELFMAG0 && hdr[1] == ELFMAG1 && hdr[2] == ELFMAG2 && hdr[3] == ELFMAG3
		&& hdr[4] == EXPECTED_ELF_CLASS;
}

char *la_objsearch(const char *name, __attribute__((unused)) uintptr_t *cookie, unsigned int flag)
{
	if (flag != LA_SER_ORIG)
	{
		return const_cast<char*>(name);
	}

	if (LIBS.contains(name))
	{
		for (const auto& dir : DIRS)
		{
			char path[256];
			snprintf(path, sizeof(path), "%s/%s", dir.c_str(), name);

			std::error_code ec;
			if (!std::filesystem::exists(path, ec) || !matches_elf_class(path))
			{
				continue;
			}

			char* n = reinterpret_cast<char*>(malloc(strlen(path) + 1));
			if (!n)
			{
				break;
			}
			strcpy(n, path);
			return n;
		}
	}

	return const_cast<char*>(name);
}

unsigned int la_version(unsigned int version)
{
	const unsigned int supported = static_cast<unsigned int>(LAV_CURRENT);
	return version == 0 ? supported : (version < supported ? version : supported);
}
