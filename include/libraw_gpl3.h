#ifndef LIBRAW_GPL3_H
#define LIBRAW_GPL3_H

#include "libraw/libraw.h"

class LibRawGPL3 : public LibRaw {
public:
    LibRawGPL3() : LibRaw() {}
    
    // GPL3 demosaic pack methods
    void amaze_demosaic_RT();
    void CA_correct_RT(float cared, float cablue);
    void cfa_impulse_gauss(float lclean, float cclean);
    void cfa_linedn(float linenoise);
    void green_equilibrate(float thresh);

    // Callback setters (since callbacks is protected in LibRaw)
    void set_interpolate_bayer_callback(process_step_callback cb) {
        callbacks.interpolate_bayer_cb = cb;
    }
};

#endif // LIBRAW_GPL3_H
