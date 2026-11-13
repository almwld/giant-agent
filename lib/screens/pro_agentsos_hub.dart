import 'package:flutter/material.dart';
import '../theme/pro_theme.dart';
import '../widgets/pro_app_bar.dart';
import 'pro_dashboard.dart';
import 'pro_task_manager.dart';
import 'pro_agent_fleet.dart';
import 'pro_battle_card.dart';
import 'pro_integrations.dart';
import 'pro_advanced_config.dart';

class ProAgentsOsHub extends StatelessWidget {
 const ProAgentsOsHub({super.key});
 @override Widget build(BuildContext context)=>Scaffold(
  backgroundColor:ProTheme.bgDark,
  appBar:const ProAppBar(title:'Control Center',breadcrumb:'GIANT AGENT / AGENTSOS'),
  body:Container(decoration:const BoxDecoration(gradient:ProTheme.bgGradient),child:GridView.count(
   padding:const EdgeInsets.all(16),crossAxisCount:MediaQuery.sizeOf(context).width>700?2:1,
   childAspectRatio:MediaQuery.sizeOf(context).width>700?3.6:3.0,crossAxisSpacing:12,mainAxisSpacing:12,
   children:[
    _tile(context,'Dashboard','Runtime health and execution metrics',Icons.dashboard_outlined,const ProDashboard()),
    _tile(context,'Task Manager','Durable task lifecycle and recovery',Icons.task_alt,const ProTaskManager()),
    _tile(context,'Agent Fleet','Subagent lifecycle and status',Icons.smart_toy_outlined,const ProAgentFleet()),
    _tile(context,'Battle Cards','Competitor intelligence workspace',Icons.insights_outlined,const ProBattleCard()),
    _tile(context,'Integrations','MCP servers and connected tools',Icons.hub_outlined,const ProIntegrations()),
    _tile(context,'Advanced Configuration','Runtime and provider preferences',Icons.tune,const ProAdvancedConfig()),
   ],
  )),
 );
 Widget _tile(BuildContext context,String title,String subtitle,IconData icon,Widget page)=>Card(
  color:ProTheme.bgCard,shape:RoundedRectangleBorder(borderRadius:BorderRadius.circular(18),side:BorderSide(color:ProTheme.neonGreen.withOpacity(.2))),
  child:ListTile(contentPadding:const EdgeInsets.symmetric(horizontal:18,vertical:10),
   leading:Container(width:48,height:48,decoration:BoxDecoration(color:ProTheme.neonGreen.withOpacity(.08),borderRadius:BorderRadius.circular(14)),child:Icon(icon,color:ProTheme.neonGreen)),
   title:Text(title,style:const TextStyle(color:ProTheme.textPrimary,fontWeight:FontWeight.bold)),
   subtitle:Text(subtitle,style:const TextStyle(color:ProTheme.textSecondary,fontSize:12)),
   trailing:const Icon(Icons.chevron_right,color:ProTheme.neonGreen),
   onTap:()=>Navigator.of(context).push(MaterialPageRoute(builder:(_)=>page)),
  ),
 );
}
