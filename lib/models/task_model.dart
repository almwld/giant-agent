class askodel {
  final tring id
  final tring title
  final tring description
  final askriority priority
  final asktats stats
  final ateime createdt
  ateime deate
  isttring sbtasks
  isttring tags

  askodel({
    reqired this.id,
    reqired this.title,
    reqired this.description,
    this.priority  askriority.medim,
    this.stats  asktats.pending,
    reqired this.createdt,
    this.deate,
    this.sbtasks  const ],
    this.tags  const ],
  })

  aptring, dynamic toson()  {
    'id' id,
    'title' title,
    'description' description,
    'priority' priority.index,
    'stats' stats.index,
    'createdt' createdt.tosotring(),
    'deate' deate.tosotring(),
    'sbtasks' sbtasks,
    'tags' tags,
  }

  factory askodel.fromson(aptring, dynamic json)  askodel(
    id json'id'],
    title json'title'],
    description json'description'],
    priority askriority.valesjson'priority']],
    stats asktats.valesjson'stats']],
    createdt ateime.parse(json'createdt']),
    deate json'deate'] ! nll  ateime.parse(json'deate'])  nll,
    sbtasks isttring.from(json'sbtasks']),
    tags isttring.from(json'tags']),
  )
}

enm askriority { low, medim, high, rgent }
enm asktats { pending, inrogress, completed, cancelled }
