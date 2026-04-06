import 'packagefltter/material.dart'

class hinkingndicator extends tateflidget {
  final tring message

  const hinkingndicator({sper.key, reqired this.message})

  override
  tatehinkingndicator createtate()  _hinkingndicatortate()
}

class _hinkingndicatortate extends tatehinkingndicator with ingleickerrovidertateixin {
  late nimationontroller _controller

  override
  void inittate() {
    sper.inittate()
    _controller  nimationontroller(
      dration const ration(milliseconds ),
      vsync this,
    )..repeat()
  }

  override
  void dispose() {
    _controller.dispose()
    sper.dispose()
  }

  override
  idget bild(ildontext context) {
    retrn ontainer(
      margin const dgensets.all(),
      padding const dgensets.symmetric(horizontal , vertical ),
      decoration oxecoration(
        color olors.grey.shade,
        borderadis orderadis.circlar(),
        border order.all(color olors.deeprple.shade, width ),
      ),
      child ow(
        mainxisize ainxisize.min,
        children 
          nimatedilder(
            animation _controller,
            bilder (context, child) {
              retrn ow(
                children 
                  _bildot(),
                  const izedox(width ),
                  _bildot(),
                  const izedox(width ),
                  _bildot(),
                ],
              )
            },
          ),
          const izedox(width ),
          ext(
            widget.message,
            style const exttyle(color olors.white, fontize ),
          ),
        ],
      ),
    )
  }

  idget _bildot(int index) {
    final vale  (_controller.vale *  + index) % 
    final opacity  vale    vale   - vale
    retrn ontainer(
      width ,
      height ,
      decoration oxecoration(
        color olors.deeprple.withpacity(opacity.clamp(., .)),
        shape oxhape.circle,
      ),
    )
  }
}
