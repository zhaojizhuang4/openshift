# $1 the deployments name
# $2 the number of replicas to check
function checkDeployment {
  deploy=$1
  replicas=$2
  skipRestartCheck=${3:-false}

  echo
  Info $SEPARATOR
  Info "Checking the deployment of $deploy. Please wait."
  CHECK_START=$(date +%s)

  while : 
  do
    if [[ $(($(date +%s) - $CHECK_START)) -ge $timeout ]]; then
      Fail "$deploy took longer than the timeout of $timeout seconds"
    fi

    names=`oc get pods | grep -i $deploy | awk '{print $1}'` || true

    count=`echo "$names" | wc -l`
    if [[ ! count -eq $replicas ]]; then
      Debug "Expecting $replicas running pods but only found $count. Waiting for the other pod to start."
    else
      running=0;
      for name in $names; do
        state=`oc get -o template pod $name --template="{{range \\$status := .status.containerStatuses}}{{\\$status.ready}}{{end}}"`
        if [[ $state == "true" ]]; then
          running=$(($running+1))
          Debug "$deploy has one replica in the 'Running' State. $running/$replicas"
        elif [[ -z $state ]]; then
          Debug "$name has not yet started to be deploy. Waiting for it to start."
        elif [[ $state == "" ]] || [[ $state == "false" ]]; then
          Debug "$name is currently not ready. Waiting for it to enter the 'ready' state."
        else
          Warn "$name is in an unexpected state: \"$state\"."
        fi
      done

      if [[ running -eq $replicas ]]; then
        Info "All replicas for $name are in the running state. Checking if they had any restarts"
        restarts=`oc get pods | grep -i $name | awk '{print $4}'` || true
        for restart in $restarts; do
          if [[ ! $restart -eq 0 ]]; then
            if [[ $skipRestartCheck == "true" ]]; then
              Info "A replica for $name had $restart restarts. Expected, test not marked as a failure."
            else
              Fail "A replica for $name had $restart restart(s). Test failed"
            fi
          fi
        done
        Info "All replicas for $name had zero restarts"
        return
      fi
    fi

    sleep 1
  done
}

function undeploy {
  type=$1
  name=$2

  undeployStart=$(date +%s)

  oc delete $type $name &> /dev/null || true

  while : 
  do
    if [[ $(($(date +%s) - $undeployStart)) -ge $timeout ]]; then
      Fail "Undeploy took longer than the timeout of $timeout seconds"
    fi

    deployment=`oc get $type $name` &> /dev/null || true

    if [[ -z $deployment ]]; then
      break
    fi

    Debug "Waiting for $type $name to be undeployed."

    sleep 1
  done
}
