#define LIBRAW_LIBRARY_BUILD
#include "libraw/libraw.h"
#include "internal/dcraw_defs.h"

#define CLASS LibRaw::

// Include GPL3 files from the fetched source
// Note: These are included as part of the LibRaw class
#include "amaze_demosaic_RT.cc"
#include "CA_correct_RT.cc"
#include "cfa_impulse_gauss.c"
#include "cfa_linedn_new.c"
#include "green_equi.c"
