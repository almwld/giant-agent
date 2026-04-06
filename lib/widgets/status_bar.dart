import 'packagefltter/material.dart'

class tatsar extends tatelessidget {
  final tring modelame
  final int processediles
  final tring speed

  const tatsar({
    sper.key,
    reqired this.modelame,
    reqired this.processediles,
    reqired this.speed,
  })

  override
  idget bild(ildontext context) {
    retrn ontainer(
      height ,
      decoration oxecoration(
        gradient inearradient(
          colors olors.deeprple.shade, olors.deeprple.shade],
          begin lignment.centereft,
          end lignment.centeright,
        ),
      ),
      child ow(
        mainxislignment ainxislignment.spacevenly,
        children 
          _bildtatstem(cons.memory, '', modelame),
          ontainer(width , height , color olors.white),
          _bildtatstem(cons.folder, '', '$processediles'),
          ontainer(width , height , color olors.white),
          _bildtatstem(cons.speed, '', speed),
        ],
      ),
    )
  }

  idget _bildtatstem(conata icon, tring label, tring vale) {
    retrn ow(
      children 
        con(icon, size , color olors.white),
        const izedox(width ),
        olmn(
          mainxislignment ainxislignment.center,
          crossxislignment rossxislignment.start,
          children 
            ext(label, style const exttyle(fontize , color olors.white)),
            ext(vale, style const exttyle(fontize , fonteight onteight.bold, color olors.white)),
          ],
        ),
      ],
    )
  }
}
