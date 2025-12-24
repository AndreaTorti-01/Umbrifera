#define LIBRAW_LIBRARY_BUILD
#include "libraw/libraw.h"
#include "internal/dcraw_defs.h"
#include "libraw_gpl3.h"

#define CLASS LibRawGPL3::

// Include GPL3 files from the fetched source
// Note: These are included as part of the LibRawGPL3 class
#include "amaze_demosaic_RT.cc"
#include "CA_correct_RT.cc"
#include "cfa_impulse_gauss.c"
#include "cfa_linedn_new.c"
#include "green_equi.c"
