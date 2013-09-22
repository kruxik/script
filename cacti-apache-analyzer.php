#!/usr/local/bin/php
<?php
// argument parsing
$shortopts  = "";
$shortopts .= "c:";  // --config
$shortopts .= "l:";  // --log
$shortopts .= "i:"; // --index
$shortopts .= "w";	// --write
$shortopts .= "n";	// --nice output
$shortopts .= "s";	// --suggest
$shortopts .= "h";   // --help

$longopts  = array(
    "config:",  // 
    "log:",     // 
    "index:",  // Optional value
	"write",	// write
	"nice",		// nice
	"suggest",	// suggest
    "help",     // No value
);
//$options = getopt($shortopts, $longopts); //not working until PHP5.3
$options = getopt($shortopts);

// help
if((isset($options["h"]) && is_bool($options["h"])) || (isset($options["help"]) && is_bool($options["help"])))
{
    echo "cacti-apache-analyzer.php - analyze Apache log and output stats\n";
    echo "Usage: cacti-apache-analyzer.php [OPTIONS] FILE\n";
/*        echo "\t-c,  --config   CONFIG_FILE     Parse config file of analyzer definitions\n";
        echo "\t-i,  --index    NUMBER          Index of a request column in an Apache log file (default: 8)\n";
        echo "\t-l,  --log      LOG_FILE        Apache log file, form which we parse data\n";
        echo "\t-h,  --help                     This help\n";*/
        echo "\t-c,  CONFIG_FILE     Parse config file of analyzer definitions\n";
        echo "\t-i,  NUMBER          Index of a request column in an Apache log file (default: 8)\n";
        echo "\t-l,  LOG_FILE        Apache log file, form which we parse data\n";
		echo "\t-n,                  Nice formated human readable output\n";
		echo "\t-s,                  Suggest pages to by optimized (load sort)\n";
		echo "\t-w,                  Write other request (without no exact filter) to a file 'other.log'\n";
        echo "\t-h,                  This help\n";
    die();
}

// check if log is specified
if(isset($options["l"]) || isset($options["log"]))
{
    is_string($logfile = $options["l"]) === false ? $logfile = $options["log"] : null;

    if(is_string($logfile) && is_file($logfile) && is_readable($logfile))
    {
        if(!($file = fopen($logfile, 'r')))
            die("Can't load given log file '{$file}'!\n");
    }
    else
        die("Invalid log file!\n");
}
else
    die("A log file isn't specified. Please provide a log file!\n");

if(isset($options["c"]) || isset($options["config"]))
{
    is_string($config = $options["c"]) === false ? $config = $options["config"] : null;

    if(is_string($config) && is_file($config) && is_readable($config))
    {
        if(!require($config))
            die("Can't load given config file '{$config}'!\n");
    }
    else
        die("Invalid config file!\n");
}
else
    die("A config file isn't specified. Please provide a config file!\n");


if(isset($options["i"]) || isset($options["index"]))
{
    is_string($var = $options["i"]) === false ? $var = $options["index"] : null;

    if(is_numeric($var))
        $request_index = (int)$var;
    else
        die("Invalid index number!");
}
else
    $request_index = 8;

if(isset($options["w"]) || isset($options["write"]))
	$write_other = true;
else
	$write_other = false;

if(isset($options["n"]) || isset($options["nice"]))
	$nice = true;
else
	$nice = false;

if(isset($options["s"]) || isset($options["suggest"]))
	$suggest = true;
else
	$suggest = false;

// Config part
$iter = 0;
$result = array();

if(!isset($request_index))
    $request_index = 8;

if(!isset($types))
    $types = array('other' => '.*');

init();

if($file)
{
	$hit_type = null;
	$is_varnish = false;

    while(!feof($file))
    {
        $line_pieces = explode(' ', fgets($file));
		$last_column = trim($line_pieces[count($line_pieces) - 1]);

        // test if line is valid
        if(!isset($line_pieces[$request_index]))
            continue;

        $request = $line_pieces[$request_index];

		if($last_column == 'hit' || $last_column == 'miss')
		{
			$is_varnish = true;
			$hit_type = $last_column;
			$time = round($line_pieces[count($line_pieces) - 2] * 1000);
			$request = preg_replace("#http(s){0,1}://[^/]+#", "", $request);
		}
		else
		{
			$hit_type = 'hit';
			$time = explode('/', $last_column);

			if(!isset($time[1]))
				continue;

			$time = round($time[1] / 1000);
		}

		if(preg_match('/^50.$/', $line_pieces[$request_index + 2]))
		{
			analyze('error_500', '50.', $line_pieces[$request_index + 2], $time, $hit_type);
		}
		elseif(preg_match("/^40.$/", $line_pieces[$request_index + 2]))
		{
			analyze('error_400', '40.', $line_pieces[$request_index + 2], $time, $hit_type);
		}
		elseif(preg_match("/POST$/", $line_pieces[$request_index - 1]))
		{
			analyze('POST', 'POST', $line_pieces[$request_index - 1], $time, $hit_type);
		}
		else
		{
			foreach($types as $type => $val)
			{
				if(analyze($type, $val, $request, $time, $hit_type))
				{
					if($write_other && $type == 'other')
					{
						$other = fopen('other.log', 'a');
						fwrite($other, $request . "\n");
						fclose($other);
					}

					if(strpos($type, 'x_') === 0)
						continue;
					else
						break;
				}
			}
		}
    }

    fclose($file);
}

compute();

if($suggest)
	suggest();
else
	output();

function init()
{
    foreach($GLOBALS['types'] as $type => $val)
    {
        $GLOBALS['result'][$type]['hit']['count'] = 0;
        $GLOBALS['result'][$type]['hit']['time'] = 0;
        $GLOBALS['result'][$type]['hit']['data'] = array();
        $GLOBALS['result'][$type]['hit']['top10b'] = 0;
        $GLOBALS['result'][$type]['hit']['top10w'] = 0;
        $GLOBALS['result'][$type]['hit']['average'] = 0;

        $GLOBALS['result'][$type]['miss']['count'] = 0;
        $GLOBALS['result'][$type]['miss']['time'] = 0;
        $GLOBALS['result'][$type]['miss']['data'] = array();
        $GLOBALS['result'][$type]['miss']['top10b'] = 0;
        $GLOBALS['result'][$type]['miss']['top10w'] = 0;
        $GLOBALS['result'][$type]['miss']['average'] = 0;
    }
}

function analyze($type, $regex, $request, $time, $hit_type)
{
    if(!isset($GLOBALS['types'][$type]))
        return false;

    $regex = '/' . str_replace('/', '\/', $regex) . '/';
    if(preg_match($regex, $request))
    {
        $GLOBALS['result'][$type][$hit_type]['count']++;
        $GLOBALS['result'][$type][$hit_type]['data'][] = $time;
        $GLOBALS['result'][$type][$hit_type]['time'] += $time;

        return true;
    }

    return false;
}

function format_type($type, $hit_type)
{
	if($GLOBALS['is_varnish'])
		$append = '-' . $hit_type;
	else
		$append = '';

	if(strpos($type, 'x_') === 0)
		return substr($type, 2) . $append;
	else
		return $type . $append;
}

function compute()
{
    foreach($GLOBALS['types'] as $type => $val)
    {
		foreach($GLOBALS['result'][$type] as $hit_type => $data)
		{
			if($data['count'] != 0)
			{
				$GLOBALS['result'][$type][$hit_type]['average'] = round($data['time'] / $data['count']);

				// Calculate TOP 10 Best
				sort($GLOBALS['result'][$type][$hit_type]['data']);

				$limit_max = round($GLOBALS['result'][$type][$hit_type]['count'] / 10);
				$sample = array();
				$sample[] = current($GLOBALS['result'][$type][$hit_type]['data']);
				for($i = 0; $i < $limit_max; $i++)
				{
					$pom = next($GLOBALS['result'][$type][$hit_type]['data']);

					if($pom == false)
						break;

					$sample[] = $pom;
				}

				$GLOBALS['result'][$type][$hit_type]['top10b'] = round(array_sum($sample) / count($sample));

				// Calculate TOP 10 Worst
				$GLOBALS['result'][$type][$hit_type]['data'] = array_reverse($GLOBALS['result'][$type][$hit_type]['data']);

				$sample = array();
				$sample[] = current($GLOBALS['result'][$type][$hit_type]['data']);
				for($i = 0; $i < $limit_max; $i++)
				{
					$pom = next($GLOBALS['result'][$type][$hit_type]['data']);

					if($pom == false)
						break;

					$sample[] = $pom;
				}

				$GLOBALS['result'][$type][$hit_type]['top10w'] = round(array_sum($sample) / count($sample));
			}
		}
    }
}

function output()
{
    foreach($GLOBALS['types'] as $type => $val)
    {
		foreach($GLOBALS['result'][$type] as $hit_type => $data)
		{
			if(!$GLOBALS['is_varnish'] && $hit_type == 'miss')
				continue;

			if($data['count'] != 0)
			{
				if($GLOBALS['nice'])
					printf("%-30s count: %8d, average: %8d, 10wa: %8d, 10ba: %8d\n", format_type($type, $hit_type), $data['count'], $data['average'], $data['top10w'], $data['top10b']);
				else
					printf("%s count:%d average:%d 10wa:%d 10ba:%d\n", format_type($type, $hit_type), $data['count'], $data['average'], $data['top10w'], $data['top10b']);
			}
			else
			{
				if($GLOBALS['nice'])
					printf("%-30s count: %8d, average: %8d, 10wa: %8d, 10ba: %8d\n", format_type($type, $hit_type), 0, 0, 0, 0);
				else
					printf("%s count:0 average:0 10wa:0 10ba:0\n", format_type($type, $hit_type));
			}
		}
    }
}

// Neni zde zapracovan hit_type!!!
// Neni zde zapracovan hit_type!!!
// Neni zde zapracovan hit_type!!!
// Neni zde zapracovan hit_type!!!
// Neni zde zapracovan hit_type!!!
// Neni zde zapracovan hit_type!!!
// Neni zde zapracovan hit_type!!!
// Neni zde zapracovan hit_type!!!
// Neni zde zapracovan hit_type!!!
// Neni zde zapracovan hit_type!!!
// Neni zde zapracovan hit_type!!!
// Neni zde zapracovan hit_type!!!
// Neni zde zapracovan hit_type!!!
function suggest()
{
	$suggest = array();

    foreach($GLOBALS['types'] as $type => $val)
    {
		foreach($GLOBALS['result'][$type] as $hit_type => $data)
		{
			$time = round(
				($data['count'] * $data['average'] * 0.8) +
				($data['count'] * $data['top10w'] * 0.1) +
				($data['count'] * $data['top10b'] * 0.1)
			);

			$suggest[] = array(
				'req' => $type,
				'hit_type' => $hit_type,
				'time' => $time,
				'count' => $data['count'],
			);
		}
    }

	$percent = ($suggest[0]['time'] + $suggest[1]['time']) / 100;

	usort($suggest, "user_sort");

	$index = 1;
	foreach($suggest as $i => $data)
	{
		if(!$GLOBALS['is_varnish'] && $data['hit_type'] == 'miss')
			continue;

		printf("%3d. %-30s total time [ms]:%16s, percent: %5.1f, count: %8d\n", $index, format_type($data['req'], $data['hit_type']), number_format($data['time']), round($data['time'] / $percent, 1), $data['count']);
		$index++;
	}
}

function user_sort($a, $b)
{
	if($a['time'] == $b['time'])
		return 0;
	else
		return ($a['time'] < $b['time']) ? 1 : -1;
}
