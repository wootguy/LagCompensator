#include "meta_init.h"
#include "misc_utils.h"
#include "meta_utils.h"
#include "main.h"
#include "private_api.h"

// Description of plugin
plugin_info_t Plugin_info = {
	META_INTERFACE_VERSION,	// ifvers
	"LagCompensator",	// name
	"1.0",	// version
	__DATE__,	// date
	"w00tguy",	// author
	"https://github.com/wootguy/",	// url
	"LAGC",	// logtag, all caps please
	PT_ANYTIME,	// (when) loadable
	PT_ANYPAUSE,	// (when) unloadable
};


void PluginInit() {
}

void PluginExit() {}