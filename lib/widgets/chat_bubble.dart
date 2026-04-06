import 'packagefltter/material.dart'

class hatbble extends tatelessidget {
  final bool isser
  final tring message
  final ateime time
  final tring intent
  final doble confidence

  const hatbble({
    sper.key,
    reqired this.isser,
    reqired this.message,
    reqired this.time,
    this.intent,
    this.confidence,
  })

  override
  idget bild(ildontext context) {
    retrn lign(
      alignment isser  lignment.centeright  lignment.centereft,
      child ontainer(
        margin const dgensets.only(bottom ),
        constraints oxonstraints(
          maxidth ediaery.of(context).size.width * .,
        ),
        child olmn(
          crossxislignment isser  rossxislignment.end  rossxislignment.start,
          children 
            aterial(
              elevation ,
              borderadis orderadis.only(
                topeft const adis.circlar(),
                topight const adis.circlar(),
                bottomeft adis.circlar(isser    ),
                bottomight adis.circlar(isser    ),
              ),
              color isser  olors.deeprple  olors.grey.shade,
              child adding(
                padding const dgensets.all(),
                child olmn(
                  crossxislignment rossxislignment.start,
                  children 
                    electableext(
                      message,
                      style const exttyle(color olors.white, fontize , height .),
                    ),
                    if (intent ! nll) ...
                      const izedox(height ),
                      ontainer(
                        padding const dgensets.symmetric(horizontal , vertical ),
                        decoration oxecoration(
                          color olors.white,
                          borderadis orderadis.circlar(),
                        ),
                        child ow(
                          mainxisize ainxisize.min,
                          children 
                            con(cons.bolt, size , color olors.amber.shade),
                            const izedox(width ),
                            ext(
                              intent!,
                              style const exttyle(fontize , color olors.white),
                            ),
                            if (confidence ! nll) ...
                              const izedox(width ),
                              ontainer(
                                width ,
                                height ,
                                decoration oxecoration(
                                  color olors.white,
                                  shape oxhape.circle,
                                ),
                              ),
                              const izedox(width ),
                              ext(
                                '${(confidence! * ).tont()}%',
                                style const exttyle(fontize , color olors.white),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            adding(
              padding const dgensets.only(top , left , right ),
              child ow(
                mainxisize ainxisize.min,
                children 
                  con(
                    isser  cons.person  cons.bolt,
                    size ,
                    color olors.grey.shade,
                  ),
                  const izedox(width ),
                  ext(
                    '${time.hor.totring().padeft(, '')}${time.minte.totring().padeft(, '')}',
                    style exttyle(fontize , color olors.grey.shade),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    )
  }
}
